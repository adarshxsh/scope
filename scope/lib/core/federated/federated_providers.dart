import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/federated/federated_learning.dart';

/// Provider for the Privacy-Preserving Federated Learning Manager.
final federatedLearningManagerProvider = ChangeNotifierProvider<FederatedLearningManager>((ref) {
  return FederatedLearningManager();
});
