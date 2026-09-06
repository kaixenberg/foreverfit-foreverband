"""Phone-only variant of train_fall_model.py — same architecture and
subject-split methodology, trained on windows_phone_only.npz (6 channels:
real phone accel + waist-sensor gyro proxy) instead of the wrist+phone
9-channel set. See ml/README.md for why this exists.
"""

from pathlib import Path

import numpy as np
import tensorflow as tf
from sklearn.metrics import classification_report, confusion_matrix
from sklearn.utils.class_weight import compute_class_weight

DATA_PATH = Path(__file__).parent / "data" / "processed" / "windows_phone_only.npz"
MODEL_PATH = Path(__file__).parent / "data" / "fall_model_phone_only.keras"

TRAIN_SUBJECTS = set(range(1, 15))  # 1-14
VAL_SUBJECTS = {15, 16, 17}
TEST_SUBJECTS = {18, 19}


def build_model(input_shape: tuple[int, int]) -> tf.keras.Model:
    inputs = tf.keras.Input(shape=input_shape)
    x = tf.keras.layers.BatchNormalization()(inputs)
    x = tf.keras.layers.Conv1D(32, 5, activation="relu", padding="same")(x)
    x = tf.keras.layers.MaxPooling1D(2)(x)
    x = tf.keras.layers.Conv1D(64, 5, activation="relu", padding="same")(x)
    x = tf.keras.layers.MaxPooling1D(2)(x)
    x = tf.keras.layers.GlobalAveragePooling1D()(x)
    x = tf.keras.layers.Dense(32, activation="relu")(x)
    x = tf.keras.layers.Dropout(0.3)(x)
    outputs = tf.keras.layers.Dense(1, activation="sigmoid")(x)
    model = tf.keras.Model(inputs, outputs)
    model.compile(
        optimizer="adam",
        loss="binary_crossentropy",
        metrics=["accuracy", tf.keras.metrics.Precision(name="precision"),
                 tf.keras.metrics.Recall(name="recall")],
    )
    return model


def split_by_subject(X, y, subjects, subject_set):
    mask = np.isin(subjects, list(subject_set))
    return X[mask], y[mask]


def main() -> None:
    data = np.load(DATA_PATH)
    X, y, subjects = data["X"], data["y"], data["subjects"]

    X_train, y_train = split_by_subject(X, y, subjects, TRAIN_SUBJECTS)
    X_val, y_val = split_by_subject(X, y, subjects, VAL_SUBJECTS)
    X_test, y_test = split_by_subject(X, y, subjects, TEST_SUBJECTS)

    print(f"Train: {X_train.shape}, Val: {X_val.shape}, Test: {X_test.shape}")
    print(f"Train fall ratio: {y_train.mean():.3f}, "
          f"Val: {y_val.mean():.3f}, Test: {y_test.mean():.3f}")

    class_weights = compute_class_weight(
        class_weight="balanced", classes=np.array([0, 1]), y=y_train
    )
    class_weight_dict = {0: class_weights[0], 1: class_weights[1]}
    print(f"Class weights: {class_weight_dict}")

    model = build_model(input_shape=X_train.shape[1:])
    model.summary()

    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_loss", patience=8, restore_best_weights=True
        ),
    ]

    model.fit(
        X_train,
        y_train,
        validation_data=(X_val, y_val),
        epochs=60,
        batch_size=32,
        class_weight=class_weight_dict,
        callbacks=callbacks,
        verbose=2,
    )

    print("\n=== Test set evaluation ===")
    y_pred_prob = model.predict(X_test, verbose=0).ravel()
    y_pred = (y_pred_prob > 0.5).astype(int)

    print(classification_report(y_test, y_pred, target_names=["ADL", "Fall"]))
    print("Confusion matrix (rows=true, cols=pred):")
    print(confusion_matrix(y_test, y_pred))

    model.save(MODEL_PATH)
    print(f"\nSaved model to {MODEL_PATH}")


if __name__ == "__main__":
    main()
