"""Unit and integration tests for tflite_exporter."""

from __future__ import annotations

from pathlib import Path
import pytest
import numpy as np
import tensorflow as tf

from training.config import FEATURE_VECTOR_SIZE
from training.export.tflite_exporter import (
    export_float32_tflite,
    export_quantized_tflite,
    export_saved_model,
    validate_tflite_model,
    _representative_dataset,
)


@pytest.fixture
def dummy_keras_model() -> tf.keras.Model:
    inputs = tf.keras.Input(shape=(FEATURE_VECTOR_SIZE,), name="features")
    x = tf.keras.layers.Dense(32, activation="relu")(inputs)
    outputs = tf.keras.layers.Dense(1, name="score")(x)
    model = tf.keras.Model(inputs=inputs, outputs=outputs)
    model.compile(optimizer="adam", loss="mse")
    return model


@pytest.fixture
def dummy_saved_model(dummy_keras_model: tf.keras.Model, tmp_path: Path) -> Path:
    export_dir = tmp_path / "saved_model"
    return export_saved_model(dummy_keras_model, export_dir)


def test_export_saved_model_invalid_type():
    with pytest.raises(TypeError, match="Expected tf.keras.Model"):
        export_saved_model("not_a_model", Path("/tmp/invalid"))


def test_export_float32_tflite_success(dummy_saved_model: Path, tmp_path: Path):
    out_file = tmp_path / "model_float32.tflite"
    result = export_float32_tflite(dummy_saved_model, out_file)

    assert result.exists()
    assert result == out_file
    assert out_file.stat().st_size > 0

    # Validate exported TFLite model structure and signatures
    telemetry = validate_tflite_model(out_file, expected_feature_size=FEATURE_VECTOR_SIZE)
    assert telemetry["input_shape"] == [1, FEATURE_VECTOR_SIZE]
    assert telemetry["input_dtype"] == "<class 'numpy.float32'>"


def test_export_quantized_tflite_with_numpy_data(
    dummy_saved_model: Path, tmp_path: Path
):
    out_quant = tmp_path / "model_quantized.tflite"
    out_float = tmp_path / "model_float.tflite"

    rep_data = np.random.randn(100, FEATURE_VECTOR_SIZE).astype(np.float32)

    export_quantized_tflite(
        dummy_saved_model, out_quant, representative_data=rep_data
    )
    export_float32_tflite(dummy_saved_model, out_float)

    assert out_quant.exists()
    quant_size = out_quant.stat().st_size
    float_size = out_float.stat().st_size

    assert quant_size > 0
    # Quantized model should be smaller than unquantized float32 model
    assert quant_size < float_size

    telemetry = validate_tflite_model(out_quant, expected_feature_size=FEATURE_VECTOR_SIZE)
    assert telemetry["input_shape"] == [1, FEATURE_VECTOR_SIZE]


def test_export_quantized_tflite_with_callable_generator(
    dummy_saved_model: Path, tmp_path: Path
):
    out_file = tmp_path / "model_quant_callable.tflite"

    def custom_generator():
        for _ in range(10):
            yield [np.random.randn(1, FEATURE_VECTOR_SIZE).astype(np.float32)]

    export_quantized_tflite(
        dummy_saved_model, out_file, representative_data=custom_generator
    )

    assert out_file.exists()
    telemetry = validate_tflite_model(out_file, expected_feature_size=FEATURE_VECTOR_SIZE)
    assert telemetry["input_shape"] == [1, FEATURE_VECTOR_SIZE]


def test_export_quantized_tflite_no_representative_data(
    dummy_saved_model: Path, tmp_path: Path
):
    out_file = tmp_path / "model_dynamic_range.tflite"
    export_quantized_tflite(dummy_saved_model, out_file, representative_data=None)

    assert out_file.exists()
    telemetry = validate_tflite_model(out_file, expected_feature_size=FEATURE_VECTOR_SIZE)
    assert telemetry["input_shape"] == [1, FEATURE_VECTOR_SIZE]


def test_validate_tflite_model_feature_size_mismatch(
    dummy_saved_model: Path, tmp_path: Path
):
    out_file = tmp_path / "model.tflite"
    export_float32_tflite(dummy_saved_model, out_file)

    with pytest.raises(
        ValueError, match="input feature vector size mismatch: expected 128, got 63"
    ):
        validate_tflite_model(out_file, expected_feature_size=128)


def test_validate_tflite_model_shape_mismatch(
    dummy_saved_model: Path, tmp_path: Path
):
    out_file = tmp_path / "model.tflite"
    export_float32_tflite(dummy_saved_model, out_file)

    with pytest.raises(ValueError, match="input shape mismatch"):
        validate_tflite_model(
            out_file, expected_input_shape=(1, 100), expected_feature_size=None
        )


def test_validate_tflite_model_empty_bytes():
    with pytest.raises(ValueError, match="binary content is empty"):
        validate_tflite_model(b"")


def test_validate_tflite_model_corrupt_bytes():
    with pytest.raises(ValueError, match="Invalid or corrupt TFLite model"):
        validate_tflite_model(b"not_a_valid_tflite_flatbuffer_bytes")


def test_validate_tflite_model_file_not_found():
    with pytest.raises(FileNotFoundError, match="TFLite model binary not found"):
        validate_tflite_model(Path("/tmp/non_existent_file.tflite"))


def test_representative_dataset_validation():
    # 1. Empty array
    with pytest.raises(ValueError, match="features array is empty"):
        _representative_dataset(np.array([]))

    # 2. Invalid rank (1D)
    with pytest.raises(ValueError, match="must be a 2D matrix"):
        _representative_dataset(np.ones((63,)))

    # 3. Wrong feature vector size
    with pytest.raises(ValueError, match="feature size mismatch"):
        _representative_dataset(np.ones((10, 10)), expected_feature_size=63)


def test_export_nonexistent_saved_model_dir(tmp_path: Path):
    non_existent = tmp_path / "does_not_exist"
    out_file = tmp_path / "out.tflite"

    with pytest.raises(FileNotFoundError, match="SavedModel directory does not exist"):
        export_float32_tflite(non_existent, out_file)

    with pytest.raises(FileNotFoundError, match="SavedModel directory does not exist"):
        export_quantized_tflite(non_existent, out_file)
