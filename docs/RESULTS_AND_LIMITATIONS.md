# Results and limitations

Numbers are reported from the October 2026 EEE 312 Group 04 report and are **not independently reproduced in this repository**.

## Held-out database evaluation

- 29 enrolled students, 493 total WAV recordings.
- Genuine identity verifications: 0 rejected out of 348; exact 95% FRR interval 0–1.1%.
- Unregistered speakers saying their own details: 0 accepted out of 87; exact 95% FAR interval 0–4.2%.
- Unregistered speakers claiming the nearest-sounding enrolled student's details: 24 accepted out of 87 for **Factor 1 alone** (27.6%).
- Phrase-gate EER: an **upper bound**, not a directly measured EER, of 1.1%.

These trials used recordings collected in the same session; results overstate performance in unconstrained live settings.

## Live demonstration observations

- 29 GUI sessions were logged on 30 September 2026.
- 17 passed Factor 1; 15 segmented the challenge into exactly 3 digits; 11 passed digit content; 5 passed the final voice gate and were granted access.
- Correct digit recognition: 42/45 individual digits; full-code recognition 13/15.
- The logs **do not contain verified ground-truth speaker labels**, so the grant rate (5/29) is **not** a true field FRR or FAR.
- Several system thresholds and models changed during the demonstration day, as documented in the report.

## Security and scientific limitations

- Challenge–response alone does **not** detect spliced recordings or synthetic speech.
- The digit-speaker model was trained from limited isolated-digit audio; the live voice gate rejected many sessions.
- The study lacks labeled multi-day live FAR/FRR, controlled SNR sweeps, direct replay experiments, and a matched head-to-head evaluation against the prior batch's implementation.
- The interface is MATLAB software only. The proposed ESP32 barrier was **not built**.

Please do not advertise this work as production-ready biometric security or claim "100% accuracy." Report denominators and evaluation conditions alongside any error percentage.
