"""Unit tests for Python DP-FedAvg federated learning module."""

import numpy as np
import pytest

from training.federated.dp_fedavg import (
    DPFedAvgClient,
    DPFedAvgServer,
    add_gaussian_noise,
    clip_gradient_l2,
    sanitize_log_text,
)


def test_sanitize_log_text():
    raw = "User user@domain.com (phone +1 555-0199) with OTP 882715 paid $99.99 with bearer token secret=xyz12345678."
    sanitized = sanitize_log_text(raw)

    assert "[REDACTED_EMAIL]" in sanitized
    assert "user@domain.com" not in sanitized
    assert "[REDACTED_PHONE]" in sanitized
    assert "[REDACTED_OTP]" in sanitized
    assert "882715" not in sanitized
    assert "[REDACTED_AMOUNT]" in sanitized
    assert "$99.99" not in sanitized
    assert "[REDACTED_CREDENTIAL]" in sanitized


def test_clip_gradient_l2():
    vec = np.array([3.0, 4.0])  # Norm is 5.0
    clipped, norm = clip_gradient_l2(vec, clip_norm=1.0)

    assert pytest.approx(norm) == 5.0
    assert pytest.approx(np.linalg.norm(clipped)) == 1.0
    assert pytest.approx(clipped[0]) == 0.6
    assert pytest.approx(clipped[1]) == 0.8

    # Within bound
    vec_small = np.array([0.1, 0.2])
    clipped_small, norm_small = clip_gradient_l2(vec_small, clip_norm=1.0)
    assert np.allclose(vec_small, clipped_small)

    with pytest.raises(ValueError):
        clip_gradient_l2(np.array([1.0, np.nan]), clip_norm=1.0)

    with pytest.raises(ValueError):
        clip_gradient_l2(vec, clip_norm=-0.5)


def test_add_gaussian_noise():
    vec = np.ones(10)
    rng = np.random.default_rng(seed=42)

    zero_noise = add_gaussian_noise(vec, noise_scale=0.0, rng=rng)
    assert np.array_equal(vec, zero_noise)

    noisy = add_gaussian_noise(vec, noise_scale=0.5, rng=rng)
    assert noisy.shape == vec.shape
    assert not np.array_equal(vec, noisy)

    with pytest.raises(ValueError):
        add_gaussian_noise(vec, noise_scale=-0.1)


def test_dp_fedavg_client_local_update():
    client = DPFedAvgClient("client_test@sec.com", clip_norm=1.0, noise_multiplier=0.05, learning_rate=0.01)

    weights = np.zeros(5)
    features = np.ones((10, 5))
    targets = np.ones(10)

    res = client.compute_local_update(weights, features, targets)

    assert res["success"] is True
    assert res["client_id"] == "[REDACTED_EMAIL]"
    assert res["delta"] is not None
    assert len(res["delta"]) == 5
    assert res["status"] == "success"


def test_dp_fedavg_client_error_recovery():
    client = DPFedAvgClient("client_nan", clip_norm=1.0)
    weights = np.zeros(5)
    invalid_features = np.full((5, 5), np.nan)
    targets = np.ones(5)

    res = client.compute_local_update(weights, invalid_features, targets)

    assert res["success"] is False
    assert res["status"] == "fallback_error"
    assert res["delta"] is None
    assert "NaN or Infinite" in res["error"]


def test_dp_fedavg_server_aggregation():
    server = DPFedAvgServer(initial_weights=np.zeros(5))

    client1_res = {
        "client_id": "c1",
        "success": True,
        "delta": np.array([0.1, 0.2, 0.3, 0.4, 0.5]),
    }
    client2_res = {
        "client_id": "c2",
        "success": True,
        "delta": np.array([0.3, 0.2, 0.1, 0.0, -0.1]),
    }

    agg_res = server.aggregate_round("round-1", [client1_res, client2_res])

    assert agg_res["success"] is True
    assert server.rounds_completed == 1
    assert np.allclose(server.weights, np.array([0.2, 0.2, 0.2, 0.2, 0.2]))
    assert len(server.audit_history) == 1
    assert server.audit_history[0]["status"] == "success"


def test_dp_fedavg_server_fallback():
    server = DPFedAvgServer(initial_weights=np.zeros(5))
    invalid_client = {"client_id": "c_bad", "success": False, "delta": None}

    agg_res = server.aggregate_round("round-failed", [invalid_client])

    assert agg_res["success"] is False
    assert server.rounds_completed == 0
    assert np.allclose(server.weights, np.zeros(5))
    assert server.audit_history[0]["status"] == "fallback_no_valid_clients"
