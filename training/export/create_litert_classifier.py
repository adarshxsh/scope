import numpy as np
import tensorflow as tf
from pathlib import Path

def train_and_export_classifier():
    # Vocab map matching assets/vocab.txt
    vocab = {
        "[PAD]": 0, "[UNK]": 1, "[CLS]": 2, "[SEP]": 3, "[MASK]": 4,
        "alert": 5, "bank": 6, "debited": 7, "spent": 8, "mom": 9, "dad": 10,
        "urgent": 11, "sale": 12, "promo": 13, "discount": 14, "msg": 15,
        "email": 16, "social": 17, "finance": 19, "health": 20, "news": 21,
        "sys": 22, "scholarship": 23
    }

    # Categories: 0: promo, 1: social, 2: sys, 3: msg, 4: finance
    X = []
    y = []

    def make_sample(tokens, label, count=50):
        for _ in range(count):
            seq = [vocab["[CLS]"]]
            for t in tokens:
                if t in vocab:
                    seq.append(vocab[t])
                else:
                    seq.append(vocab["[UNK]"])
            seq.append(vocab["[SEP]"])
            while len(seq) < 64:
                seq.append(vocab["[PAD]"])
            X.append(seq[:64])
            y.append(label)

    # 0: Promo
    make_sample(["sale", "discount", "promo"], 0, 100)
    make_sample(["sale"], 0, 50)
    make_sample(["discount"], 0, 50)
    make_sample(["promo"], 0, 50)

    # 1: Social
    make_sample(["mom", "social"], 1, 100)
    make_sample(["dad"], 1, 50)
    make_sample(["mom"], 1, 50)
    make_sample(["social"], 1, 50)

    # 2: Sys
    make_sample(["sys", "alert", "urgent"], 2, 100)
    make_sample(["alert"], 2, 50)
    make_sample(["urgent"], 2, 50)
    make_sample(["sys"], 2, 50)

    # 3: Msg
    make_sample(["msg", "email"], 3, 100)
    make_sample(["msg"], 3, 50)
    make_sample(["email"], 3, 50)

    # 4: Finance
    make_sample(["bank", "debited", "spent", "finance"], 4, 100)
    make_sample(["bank"], 4, 50)
    make_sample(["debited"], 4, 50)
    make_sample(["spent"], 4, 50)
    make_sample(["finance"], 4, 50)

    X_arr = np.array(X, dtype=np.int32)
    y_arr = np.array(y, dtype=np.int32)

    inputs = tf.keras.Input(shape=(64,), dtype=tf.int32, name="input_1")
    x = tf.keras.layers.Embedding(input_dim=5000, output_dim=16)(inputs)
    x = tf.keras.layers.GlobalAveragePooling1D()(x)
    x = tf.keras.layers.Dense(32, activation="relu")(x)
    outputs = tf.keras.layers.Dense(5, activation=None, name="logits")(x)

    model = tf.keras.Model(inputs=inputs, outputs=outputs)
    model.compile(optimizer="adam", loss=tf.keras.losses.SparseCategoricalCrossentropy(from_logits=True), metrics=["accuracy"])

    model.fit(X_arr, y_arr, epochs=30, batch_size=16, verbose=0)

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_model = converter.convert()

    output_path = Path("/app/scope/scope/assets/litert_classifier.tflite")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "wb") as f:
        f.write(tflite_model)

    print(f"Exported TFLite classifier to {output_path} ({len(tflite_model)} bytes)")

if __name__ == "__main__":
    train_and_export_classifier()
