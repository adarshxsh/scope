"""Script to train and export dedicated neural category classifier TFLite model."""

from __future__ import annotations

import os
from pathlib import Path
import numpy as np
import tensorflow as tf

ROOT_DIR = Path(__file__).resolve().parent.parent
VOCAB_PATH = ROOT_DIR / "scope" / "assets" / "vocab.txt"
OUTPUT_MODEL_PATH = ROOT_DIR / "scope" / "assets" / "category_model.tflite"

CATEGORIES = ['promo', 'social', 'sys', 'msg', 'finance']
MAX_SEQ_LEN = 64


def load_vocab(vocab_file: Path) -> dict[str, int]:
    vocab = {}
    with open(vocab_file, 'r', encoding='utf-8') as f:
        for idx, line in enumerate(f):
            word = line.strip()
            if word:
                vocab[word] = idx
    return vocab


def basic_tokenize(text: str) -> list[str]:
    import re
    normalized = text.lower()
    regex = re.compile(r"[a-zA-Z0-9]+|[^\s\w]")
    return regex.findall(normalized)


def wordpiece_tokenize(word: str, vocab: dict[str, int]) -> list[str]:
    subwords = []
    start = 0
    is_bad = False
    while start < len(word):
        end = len(word)
        cur_subword = ''
        found = False
        while start < end:
            substr = word[start:end]
            if start > 0:
                substr = '##' + substr
            if substr in vocab:
                cur_subword = substr
                found = True
                break
            end -= 1
        if not found:
            is_bad = True
            break
        subwords.append(cur_subword)
        start = end
    if is_bad:
        return ['[UNK]']
    return subwords


def tokenize_text(text: str, vocab: dict[str, int], max_len: int = MAX_SEQ_LEN) -> list[int]:
    cls_id = vocab.get('[CLS]', 101)
    sep_id = vocab.get('[SEP]', 102)
    pad_id = vocab.get('[PAD]', 0)
    unk_id = vocab.get('[UNK]', 100)

    tokens = basic_tokenize(text)
    ids = [cls_id]

    for token in tokens:
        if len(ids) >= max_len - 1:
            break
        subwords = wordpiece_tokenize(token, vocab)
        for subword in subwords:
            if len(ids) >= max_len - 1:
                break
            ids.append(vocab.get(subword, unk_id))

    if len(ids) < max_len:
        ids.append(sep_id)
    else:
        ids[max_len - 1] = sep_id

    while len(ids) < max_len:
        ids.append(pad_id)

    return ids


# Dataset samples for the 5 categories
TRAIN_DATA = [
    # 0: promo
    ("sale discount promo off 50% deal offer flash sale buy today coupon discount", 0),
    ("limited time deal extra 20% off on all items shop now discount promo", 0),
    ("exclusive offer for you get 15% discount on your next order promo sale", 0),
    ("flash sale live now save big on sneakers electronics clothing promo offer", 0),
    ("mega sale starts tonight buy 1 get 1 free offer discount promo deal", 0),
    ("special discount coupon code applied discount sale promo offer", 0),

    # 1: social
    ("liked your photo mom dad social friend followed commented mention", 1),
    ("new follower on social media someone liked your comment and replied", 1),
    ("friend request received someone mentioned you in a comment social photo", 1),
    ("john liked your story and sent a reply on social media photo comment", 1),
    ("new notification someone tagged you in a photo and commented social", 1),
    ("your video received 100 likes and 10 comments on social media", 1),

    # 2: sys
    ("otp verification code valid 10 minutes battery low system update security warning", 2),
    ("your verification code is 882715 valid for 5 minutes security sign in", 2),
    ("system update available restart to install security patch battery low", 2),
    ("use 352572 to verify your account sign-in request OTP security alert", 2),
    ("device storage full system warning clean up memory now update alert", 2),
    ("login alert new device signed into your account sys security verification", 2),

    # 3: msg
    ("hello how are you mom dad msg email chat call message reply hey there", 3),
    ("hey can you check this message reply when you are free chat msg", 3),
    ("mom sent you a message call me back when you get this chat msg", 3),
    ("meeting tomorrow at 10 am email message reply to confirm chat msg", 3),
    ("good morning hope you have a great day text message chat reply msg", 3),
    ("let us catch up later today message reply chat msg email", 3),

    # 4: finance
    ("bank debited spent rs inr account payment withdraw upi credit debit transfer", 4),
    ("your account has been debited rs 5000 for purchase at store bank payment", 4),
    ("inr 2500 credited to your account ending xx3412 bank payment transfer upi", 4),
    ("broadband bill payment of rs 799 successful bank account upi money", 4),
    ("payment failed for order rs 1200 please retry using bank card upi", 4),
    ("upi collect request received rs 499 bank transfer payment account", 4),
]


def build_and_train_model(vocab: dict[str, int]) -> tf.keras.Model:
    X_list = []
    y_list = []

    # Augment dataset samples
    for text, label in TRAIN_DATA * 50:
        ids = tokenize_text(text, vocab)
        X_list.append(ids)
        y_list.append(label)

    X = np.array(X_list, dtype=np.float32)
    y = np.array(y_list, dtype=np.int32)

    # Shuffle
    indices = np.arange(len(X))
    np.random.seed(42)
    np.random.shuffle(indices)
    X = X[indices]
    y = y[indices]

    vocab_size = max(vocab.values()) + 100

    inputs = tf.keras.Input(shape=(MAX_SEQ_LEN,), dtype="float32", name="token_ids")
    x = tf.keras.layers.Lambda(lambda t: tf.cast(t, tf.int32))(inputs)
    x = tf.keras.layers.Embedding(input_dim=vocab_size, output_dim=16)(x)
    x = tf.keras.layers.GlobalAveragePooling1D()(x)
    x = tf.keras.layers.Dense(32, activation="relu")(x)
    outputs = tf.keras.layers.Dense(5, name="category_logits")(x)

    model = tf.keras.Model(inputs=inputs, outputs=outputs, name="neural_category_classifier")
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=0.01),
        loss=tf.keras.losses.SparseCategoricalCrossentropy(from_logits=True),
        metrics=["accuracy"]
    )

    model.fit(X, y, epochs=15, batch_size=32, verbose=1)
    return model


def main():
    vocab = load_vocab(VOCAB_PATH)
    print(f"Loaded vocab of size {len(vocab)} from {VOCAB_PATH}")

    model = build_and_train_model(vocab)

    # Convert to TFLite
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_model = converter.convert()

    os.makedirs(OUTPUT_MODEL_PATH.parent, exist_ok=True)
    with open(OUTPUT_MODEL_PATH, "wb") as f:
        f.write(tflite_model)

    print(f"Successfully saved TFLite model to {OUTPUT_MODEL_PATH} ({len(tflite_model)} bytes)")


if __name__ == "__main__":
    main()
