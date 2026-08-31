# Nuvo motion model service

This is the model-facing layer behind the versioned `/motion/analyze` contract.
The Worker currently contains a deterministic baseline so the Flutter app works
before a trained model exists. This service is the replacement inference path
once the first PyTorch checkpoint is trained.

`train.py` expects JSONL records with `motion_id`, `user_id`, `label`, and
`frames`. Splits are made by user to avoid leaking the same person's movement
into both training and evaluation.
