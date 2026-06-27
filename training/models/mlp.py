"""Baseline MLP model."""

from __future__ import annotations

import tensorflow as tf

from training.config import FEATURE_VECTOR_SIZE


@tf.keras.utils.register_keras_serializable(package="attentionos")
class R2Score(tf.keras.metrics.Metric):
    """Coefficient of determination for regression."""

    def __init__(self, name: str = "r2", **kwargs):
        super().__init__(name=name, **kwargs)
        self.sum_y = self.add_weight(name="sum_y", initializer="zeros")
        self.sum_y_squared = self.add_weight(
            name="sum_y_squared", initializer="zeros"
        )
        self.sum_squared_residuals = self.add_weight(
            name="sum_squared_residuals", initializer="zeros"
        )
        self.count = self.add_weight(name="count", initializer="zeros")

    def update_state(self, y_true, y_pred, sample_weight=None):
        y_true = tf.cast(y_true, self.dtype)
        y_pred = tf.cast(y_pred, self.dtype)
        residuals = tf.square(y_true - y_pred)

        if sample_weight is not None:
            sample_weight = tf.cast(sample_weight, self.dtype)
            residuals = tf.multiply(residuals, sample_weight)

        self.sum_y.assign_add(tf.reduce_sum(y_true))
        self.sum_y_squared.assign_add(tf.reduce_sum(tf.square(y_true)))
        self.sum_squared_residuals.assign_add(tf.reduce_sum(residuals))
        self.count.assign_add(tf.cast(tf.size(y_true), self.dtype))

    def result(self):
        mean_y = tf.math.divide_no_nan(self.sum_y, self.count)
        total_sum_squares = self.sum_y_squared - self.count * tf.square(mean_y)
        return 1.0 - tf.math.divide_no_nan(
            self.sum_squared_residuals,
            total_sum_squares,
        )

    def reset_state(self):
        self.sum_y.assign(0.0)
        self.sum_y_squared.assign(0.0)
        self.sum_squared_residuals.assign(0.0)
        self.count.assign(0.0)

    def reset_states(self):
        self.reset_state()


def build_baseline_mlp(
    mean: list[float],
    stddev: list[float],
    learning_rate: float,
) -> tf.keras.Model:
    inputs = tf.keras.Input(shape=(FEATURE_VECTOR_SIZE,), name="features")
    
    # In-graph feature normalization using constants
    mean_const = tf.constant(mean, dtype=tf.float32, name="normalization_mean")
    stddev_const = tf.constant(stddev, dtype=tf.float32, name="normalization_stddev")
    x = (inputs - mean_const) / stddev_const

    x = tf.keras.layers.Dense(128, activation="relu", name="dense_128")(x)
    x = tf.keras.layers.Dropout(0.2, name="dropout_0_2")(x)
    x = tf.keras.layers.Dense(64, activation="relu", name="dense_64")(x)
    x = tf.keras.layers.Dense(32, activation="relu", name="dense_32")(x)
    outputs = tf.keras.layers.Dense(1, name="look_again_score")(x)

    model = tf.keras.Model(inputs=inputs, outputs=outputs, name="attentionos_mlp")
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=learning_rate),
        loss="mse",
        metrics=[
            tf.keras.metrics.MeanAbsoluteError(name="mae"),
            tf.keras.metrics.RootMeanSquaredError(name="rmse"),
            R2Score(name="r2"),
        ],
    )
    return model
