function cfg = vsConfig()
%VSCONFIG  Shared feature and authentication settings.
%
%   Phrase gate is learned from raw_records/; voice gate is configured here.
%
%   Expected: raw_records/ and database/ alongside ParkingSecuritySystem/.
%   Neither recordings nor trained MAT files are stored inside the code folder.

here = fileparts(mfilename('fullpath'));
cfg.PipelineVersion = 'auth-plus-three-digit-v1'; % rebuild once to retain isolated-digit templates
cfg.CodeDir       = here;
cfg.ProjectDir    = fileparts(here);
cfg.RawRecordsDir = fullfile(cfg.ProjectDir, 'raw_records');  % source recordings
cfg.DataDir       = fullfile(cfg.ProjectDir, 'database');     % persistent trained models

% ---- Phase 1: pre-processing (Modification 1) ----
cfg.TargetFs           = 8000;
cfg.PreEmphasisCoeff   = 0.95;    % H(z) = 1 - 0.95 z^-1
cfg.FrameLengthMs      = 25;
cfg.OverlapRatio       = 0.50;
cfg.VadThreshold       = 0.015;   % end-point trim, fraction of peak frame energy
cfg.SpectralSubtraction = true;    % remove steady room noise before features (spectralSubtract.m)
cfg.SSFrameMs          = 32;
cfg.SSNoiseFraction    = 0.10;    % quietest 10% of frames = noise estimate
cfg.SSOverSubtraction  = 2.0;     % alpha
cfg.SSFloor            = 0.02;    % beta

% ---- Live ambient reference (runtime only, never saved) ----
% Capture once BEFORE roll/name, then reuse for Factor 1 and Factor 2.
% Enrollment and prerecorded-file diagnostics retain the original quiet-frame
% estimator. Keep PipelineVersion unchanged: enrollment features are unchanged.
cfg.UseAmbientNoiseReference = true;
cfg.AmbientNoiseSeconds      = 3.0;
cfg.AmbientNoiseProfile      = [];   % populated ONLY during a live session

% ---- Phase 2 Path A: MFCC + Delta (Modification 2) ----
cfg.FeatureDim         = '20D';   % '10D' | '20D' | '30D'
cfg.NumMFCC            = 10;
cfg.NumMelFilters      = 26;
cfg.NFFT               = 512;
cfg.MelLowFreq         = 100;
cfg.MelHighFreq        = 4000;
cfg.DeltaWindow        = 2;       % N in the FIR regression formula
cfg.SpeechFloorDb      = 30;      % frames > 30 dB below the loudest are pauses
cfg.NumSpeakerCep      = 12;      % c1..c12 used by the speaker codebook

% ---- Speaker identification + verification ----
cfg.DatabaseFile       = fullfile(cfg.DataDir, 'EnrolledDatabase.mat');
cfg.VerifierModelFile  = fullfile(cfg.DataDir, 'VerifierModel.mat');
cfg.CohortSize         = 5;       % nearest other students used to normalise the phrase score
cfg.TargetFARUnknown   = 0.02;    % phrase gate: other phrases that may pass (trainVerifier)
cfg.CalibrationFolds   = 5;       % students held out as "unregistered" per fold
% Voice model: GMM-UBM with MAP adaptation (voiceModel.m, Reynolds et al. 2000)
cfg.NumMixtures        = 128;     % Gaussians in the background model (power of 2)
cfg.EMIterations       = 20;
cfg.LBGIterations      = 10;      % k-means passes per split when initialising the UBM
cfg.UBMMaxFrames       = 60000;   % frames used to fit the UBM (thinned uniformly)
cfg.MAPRelevance       = 16;      % r in a = n/(n+r)
% All enrolled students use the same baseline voice gate.
cfg.VoiceGate          = 0.30;
cfg.MaxAuthAttempts    = 1;
cfg.LoginSequence      = {'roll', 'name'};

% ---- Fresh three-digit challenge (second factor) ----
% Independent energy-based segmentation, original MFCC/DTW on each digit.
% Baseline voice threshold stays 0.30 until YOUR own controlled LIVE
% challenge trials justify a separately calibrated gate for that roll.
cfg.ChallengeLength             = 3;
cfg.MaxChallengeAttempts        = 1;
cfg.ChallengeTemplateSpeakers   = 6;
cfg.ChallengeBestTemplates      = 2;
cfg.ChallengeOwnWeight          = 0.60;
cfg.ChallengeMaxTakesPerDigit   = 3;     % use up to 3 takes of EACH digit
cfg.ChallengeDigitMinMargin     = 0.015; % provisional; inspect digit scores
cfg.ChallengeMinFrames          = 25;
cfg.ChallengeMinDigitFrames     = 8;
cfg.ChallengeVoiceGate          = 0.20; % baseline pending challenge-specific calibration
% Factor 2 has a SEPARATE digit-trained model. Original Factor 1 UBM and
% student models stored in EnrolledDatabase.mat remain completely unchanged.
cfg.DigitVoiceModelFile         = fullfile(cfg.DataDir,'DigitVoiceModel.mat');
cfg.Factor2CalibrationFile      = fullfile(cfg.DataDir,'DigitVoiceCalibration.mat');
cfg.DigitVoiceMaxTakesPerDigit  = 3;    % include up to three isolated takes per digit
cfg.DigitVoiceMinFramesPerDigit = 5;    % discard too-short/unusable digit takes
cfg.DigitVoiceFramesPerStudent  = 1200; % cap large collections for fair UBM
cfg.DigitVoiceMinFramesPerStudent = 75; % require usable training coverage
cfg.ChallengeLegacyVoiceDiagnostic = false; % compare old mixed-speech model (display ONLY)
cfg.ChallengeNoiseDiagnostic    = true;  % same raw audio, shared versus quiet
cfg.ChallengeNoiseDigitDiagnostic = true; % optional: extra DTWs for diagnosis
% For reliable segmentation say digits with ~0.25-0.50 s silent pauses.
cfg.ChallengeBridgeSec          = 0.12;  % bridge syllable-internal dips
cfg.ChallengeMergeMaxSec        = 0.16;
cfg.ChallengeMinCoreSec         = 0.11;
cfg.ChallengeEdgePadSec         = 0.035;
cfg.ChallengePauseLowSec        = 0.25;
cfg.ChallengePauseHighSec       = 0.50;

% ---- Capture ----
cfg.RecordFs           = 48000;   % preserve original microphone acquisition settings
cfg.InputDeviceName    = '';      % '' = Windows default microphone; otherwise part of
                                  % the device name shown at start-up, e.g. 'USB' or 'Fifine'
% Verification and microphone-check recordings remain in memory; no WAV saving.
cfg.MaxRecordSeconds   = 10;      % hard cap per utterance
cfg.NoSpeechTimeout    = 6;       % give up if nobody speaks for this long
cfg.EndSilenceSeconds  = 0.9;     % trailing silence that ends an utterance
cfg.EndRelativeDb      = 25;      % after onset, frames > 25 dB below the loudest are silence
cfg.MinSpeechSeconds   = 0.25;
cfg.StartMarginDb      = 12;      % speech = this far above the noise floor
cfg.MinSpeechLevelDb   = -55;     % ... and at least this loud (dBFS)

% ---- Optional metadata for student display names ----
cfg.SpeakersFile       = fullfile(cfg.RawRecordsDir, 'speakers.csv');
end
