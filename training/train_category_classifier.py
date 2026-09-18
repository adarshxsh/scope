"""Train and export dedicated NLP Category Classification TFLite model."""

import json
from pathlib import Path
import numpy as np
import tensorflow as tf

vocab_path = Path("scope/assets/vocab.txt")
lines = vocab_path.read_text().splitlines()
vocab = {line.strip(): i for i, line in enumerate(lines) if line.strip()}

PAD_ID = vocab.get("[PAD]", 0)
UNK_ID = vocab.get("[UNK]", 1)
CLS_ID = vocab.get("[CLS]", 2)
SEP_ID = vocab.get("[SEP]", 3)
MAX_SEQ_LEN = 64

def tokenize(text: str) -> list[int]:
    import re
    tokens = re.findall(r"[a-zA-Z0-9]+|[^\s\w]", text.lower())
    ids = [CLS_ID]
    for token in tokens:
        if len(ids) >= MAX_SEQ_LEN - 1:
            break
        # wordpiece lookup
        subwords = []
        start = 0
        is_bad = False
        while start < len(token):
            end = len(token)
            found = False
            cur_subword = ""
            while start < end:
                substr = token[start:end]
                if start > 0:
                    substr = f"##{substr}"
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
            subwords = ["[UNK]"]
        for subword in subwords:
            if len(ids) >= MAX_SEQ_LEN - 1:
                break
            ids.append(vocab.get(subword, UNK_ID))
    if len(ids) < MAX_SEQ_LEN:
        ids.append(SEP_ID)
    else:
        ids[MAX_SEQ_LEN - 1] = SEP_ID
    while len(ids) < MAX_SEQ_LEN:
        ids.append(PAD_ID)
    return ids

# Define training samples per category
# Categories: 0: promo, 1: social, 2: sys, 3: msg, 4: finance
samples = [
    # 0: promo
    ("Flash sale! Get 50% off on all items.", 0),
    ("Exclusive promo code for your next order. Save big today!", 0),
    ("Special discount offer available now. Shop today!", 0),
    ("Mega deal on electronics. Buy now and save extra cash.", 0),
    ("Limited time offer! Get 20% discount on clothing.", 0),
    ("Big discount sale is live. Hurry and save!", 0),
    ("Use promo code SAVE20 for discount on your purchase.", 0),
    ("Super sale! Buy 1 get 1 free offer.", 0),

    # 1: social
    ("Alice liked your photo on Instagram.", 1),
    ("Bob commented on your post.", 1),
    ("Charlie started following you on Twitter.", 1),
    ("You were mentioned in a story by David.", 1),
    ("Eve sent you a friend request on Facebook.", 1),
    ("Frank liked your comment on social media.", 1),
    ("New follower alert! Grace followed your profile.", 1),

    # 2: sys
    ("Your OTP verification code is 882715. Do not share with anyone.", 2),
    ("Security alert: New login detected on your account.", 2),
    ("System update available for download. Tap to install.", 2),
    ("Use verification code 492018 to reset your password.", 2),
    ("Account sign-in detected near Chennai. Review security.", 2),
    ("Password reset request received. Verification code is 1234.", 2),
    ("Warning: Unusual login attempt blocked by system.", 2),

    # 3: msg
    ("Mom: Hey, can you call me when you are free?", 3),
    ("Dad: Did you reach safely? Let me know.", 3),
    ("Meeting scheduled for 3 PM tomorrow.", 3),
    ("Hello, how are you doing today?", 3),
    ("New message from Alice: Are we still meeting today?", 3),
    ("Can you please send me the file when possible?", 3),
    ("Hey there, hope you are having a great day!", 3),

    # 4: finance
    ("Bank Alert: Your account XX3412 has been debited Rs. 2000.", 4),
    ("Payment of Rs 500 received via UPI.", 4),
    ("Credit card statement generated. Minimum amount due Rs 1200.", 4),
    ("Rs 15000 spent at Store using HDFC debit card.", 4),
    ("UPI collect request: Rs 799 requested from Fariq.", 4),
    ("SIP of Rs 99 scheduled for tomorrow. Maintain balance.", 4),
    ("Your bank account was credited with Rs 5000.", 4),
    ("Transaction alert: Rs 250 spent on food delivery.", 4),
]

# Duplicate samples with variations to increase training size
X_list = []
y_list = []

for text, cat in samples * 20: # 20 copies for robust training
    X_list.append(tokenize(text))
    y_list.append(cat)

X = np.array(X_list, dtype=np.int32)
y = np.array(y_list, dtype=np.int32)

print("Dataset shape:", X.shape, y.shape)

# Build Keras Model
# Input: [1, 64] int32
# Output: [1, 5] float32 logits
tf.keras.utils.set_random_seed(42)

inputs = tf.keras.Input(shape=(MAX_SEQ_LEN,), dtype=tf.int32, name="token_ids")
embedding = tf.keras.layers.Embedding(input_dim=len(vocab) + 50, output_dim=32, mask_zero=True)(inputs)
pooled = tf.keras.layers.GlobalAveragePooling1D()(embedding)
dense1 = tf.keras.layers.Dense(64, activation="relu")(pooled)
outputs = tf.keras.layers.Dense(5, name="logits")(dense1)

model = tf.keras.Model(inputs=inputs, outputs=outputs)
model.compile(
    optimizer=tf.keras.optimizers.Adam(learning_rate=0.01),
    loss=tf.keras.losses.SparseCategoricalCrossentropy(from_logits=True),
    metrics=["accuracy"],
)

model.fit(X, y, epochs=30, batch_size=16, verbose=1)

# Convert to TFLite
converter = tf.lite.TFLiteConverter.from_keras_model(model)
tflite_model = converter.convert()

output_path = Path("scope/assets/category_model.tflite")
output_path.write_bytes(tflite_model)
print(f"Exported category model to {output_path} ({len(tflite_model)} bytes)")
