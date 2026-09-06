"""Convert the phone-only fall-detection model to TFLite, into the
Flutter app's assets folder. See ml/README.md."""

from pathlib import Path

import tensorflow as tf

MODEL_PATH = Path(__file__).parent / "data" / "fall_model_phone_only.keras"
OUT_PATH = (
    Path(__file__).parent.parent
    / "app"
    / "health_companion"
    / "assets"
    / "models"
    / "fall_detector_phone_only.tflite"
)


def main() -> None:
    model = tf.keras.models.load_model(MODEL_PATH)

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_model = converter.convert()

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_bytes(tflite_model)

    size_kb = len(tflite_model) / 1024
    print(f"Wrote {OUT_PATH} ({size_kb:.1f} KB)")


if __name__ == "__main__":
    main()
