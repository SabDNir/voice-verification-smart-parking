# Methodology summary

Source: *Design and Implementation of a MATLAB-Based Voice Recognition Anti-Theft System for Smart Parking Infrastructure*, EEE 312 Group 04 report, October 2026. This is a concise account of the team report, not an independent reimplementation.

## Enrollment and front-end

The study enrolled 29 students using 493 recordings (17 per student). Recordings were resampled to mono 8 kHz; the pipeline used pre-emphasis, short-time framing, silence removal, spectral subtraction, and mel-frequency cepstral features. Content and speaker verification used different normalization procedures.

## Factor 1: claimed identity

Roll-number and full-name utterances were matched with template MFCC sequences using dynamic time warping (DTW); the phrase score was cohort-normalized. A 128-component diagonal-covariance GMM-UBM was trained using EM; speaker models adapted Gaussian means via MAP. The claimed user needed to pass both content and speaker gates.

## Factor 2: challenge–response

After successful Factor 1 verification, the system generated a random three-digit code. Audio segmentation used an energy envelope without access to the expected digits; each candidate segment was classified using DTW against digit templates. A separate GMM-UBM trained on isolated digits was used for final voice verification.

## Threshold calibration and uncertainty

The phrase gate threshold was learned using five-fold outsider simulations. The voice gates and digit margin were set as engineering choices; the report explicitly notes they require live data calibration. The report calculates exact binomial confidence intervals and EER bounds from observed counts and explicitly distinguishes held-out, same-session evaluations from uncontrolled live sessions.

## Scope

The code implements a MATLAB software verifier. The ESP32 controller, physical barrier, hardware RNG and authenticated actuation protocol exist **only as a design proposal** in the report; no such hardware results are claimed.
