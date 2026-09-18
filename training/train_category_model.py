"""Script to train and export the AttentionOS TFLite category classification model."""

import os
from pathlib import Path
import numpy as np
import tensorflow as tf
import keras

def main():
    np.random.seed(42)
    tf.keras.utils.set_random_seed(42)

    # Input: sequence of 64 token IDs (int32)
    inputs = keras.Input(shape=(64,), dtype="int32", name="input_ids")
    x_embed = keras.layers.Embedding(input_dim=256, output_dim=32)(inputs)
    x_pooled = keras.layers.GlobalAveragePooling1D()(x_embed)
    x_dense = keras.layers.Dense(32, activation="relu")(x_pooled)
    logits = keras.layers.Dense(5, activation=None, name="logits")(x_dense)

    model = keras.Model(inputs=inputs, outputs=logits)

    # Synthetic training data mapped to vocab.txt indices and categories
    # Categories: 0: promo, 1: social, 2: sys, 3: msg, 4: finance
    X_data = []
    y_data = []

    for _ in range(3000):
        cat = np.random.randint(0, 5)
        seq = np.zeros(64, dtype=np.int32)
        seq[0] = 2  # [CLS]
        if cat == 0:  # promo
            tokens = np.random.choice([13, 14, 15, 19], size=np.random.randint(1, 4))
        elif cat == 1:  # social
            tokens = np.random.choice([18], size=np.random.randint(1, 4))
        elif cat == 2:  # sys
            tokens = np.random.choice([6, 22, 23], size=np.random.randint(1, 4))
        elif cat == 3:  # msg
            tokens = np.random.choice([9, 10, 16], size=np.random.randint(1, 4))
        elif cat == 4:  # finance
            tokens = np.random.choice([7, 8, 20], size=np.random.randint(1, 4))

        for i, tok in enumerate(tokens):
            seq[1 + i] = tok
        seq[1 + len(tokens)] = 3  # [SEP]

        X_data.append(seq)
        y_data.append(cat)

    X_data = np.array(X_data, dtype=np.int32)
    y_data = np.array(y_data, dtype=np.int32)

    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=0.01),
        loss=keras.losses.SparseCategoricalCrossentropy(from_logits=True),
        metrics=["accuracy"],
    )

    model.fit(X_data, y_data, epochs=15, batch_size=32, verbose=0)

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_model = converter.convert()

    output_path = Path("/app/scope/scope/assets/category_model.tflite")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(tflite_model)

    print(f"Exported category model to {output_path} ({len(tflite_model)} bytes)")

if __name__ == "__main__":
    main()
