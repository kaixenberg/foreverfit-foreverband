"""Train the activity classifier (still/walking/running) on
activity_windows.npz. Same 1D-CNN family and subject-disjoint split
methodology as the fall detector (see train_fall_model_phone_only.py) —
adapted to 3-class softmax output. See ml/README.md.
"""

from pathlib import Path

import numpy as np
import tensorflow as tf
from sklearn.metrics import classification_report, confusion_matrix
from sklearn.utils.class_weight import compute_class_weight

DATA_PATH = Path(__file__).parent / "data" / "processed" / "activity_windows.npz"
MODEL_PATH = Path(__file__).parent / "data" / "activity_model.keras"

CLASSES = ["still", "walking", "running"]

# 24 subjects total — same train-heavy / small val+test split ratio used
# for the fall detector.
TRAIN_SUBJECTS = set(range(1, 19))  # 1-18
VAL_SUBJECTS = {19, 20, 21}
TEST_SUBJECTS = {22, 23, 24}


def build_model(input_shape: tuple[int, int], n_classes: int) -> tf.keras.Model:
    inputs = tf.keras.Input(shape=input_shape)
    x = tf.keras.layers.BatchNormalization()(inputs)
    x = tf.keras.layers.Conv1D(32, 5, activation="relu", padding="same")(x)
    x = tf.keras.layers.MaxPooling1D(2)(x)
    x = tf.keras.layers.Conv1D(64, 5, activation="relu", padding="same")(x)
    x = tf.keras.layers.MaxPooling1D(2)(x)
    x = tf.keras.layers.GlobalAveragePooling1D()(x)
    x = tf.keras.layers.Dense(32, activation="relu")(x)
    x = tf.keras.layers.Dropout(0.3)(x)
    outputs = tf.keras.layers.Dense(n_classes, activation="softmax")(x)
    model = tf.keras.Model(inputs, outputs)
    model.compile(
        optimizer="adam",
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
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

    class_weights = compute_class_weight(
        class_weight="balanced", classes=np.arange(len(CLASSES)), y=y_train
    )
    class_weight_dict = dict(enumerate(class_weights))
    print(f"Class weights: {class_weight_dict}")

    model = build_model(input_shape=X_train.shape[1:], n_classes=len(CLASSES))
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
        epochs=40,
        batch_size=32,
        class_weight=class_weight_dict,
        callbacks=callbacks,
        verbose=2,
    )

    print("\n=== Test set evaluation ===")
    y_pred_prob = model.predict(X_test, verbose=0)
    y_pred = np.argmax(y_pred_prob, axis=1)

    print(classification_report(y_test, y_pred, target_names=CLASSES))
    print("Confusion matrix (rows=true, cols=pred):")
    print(confusion_matrix(y_test, y_pred))

    model.save(MODEL_PATH)
    print(f"\nSaved model to {MODEL_PATH}")


if __name__ == "__main__":
    main()
