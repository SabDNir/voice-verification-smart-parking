function [featuresDyn, staticMFCC, deltaMFCC, deltaDeltaMFCC, extra] = extractMFCC_Delta(frames, fs, cfg)
%EXTRACTMFCC_DELTA  Phase 2 Path A - Modification 2.
%
% 10 static MFCCs (c0 dropped) plus FIR-regression Delta and Delta-Delta.
%
%   Delta c_t = sum_{n=1..N} n*(c_{t+n} - c_{t-n}) / (2*sum_{n=1..N} n^2)
%
% Output is [NumFrames x Dim] with Dim = 10, 20 or 30 depending on cfg.
%
% v3 adds a fifth output, extra, with two by-products of the same filterbank:
%   extra.LogEnergy   [NumFrames x 1] log of the total mel energy per frame.
%                     Used to drop pauses INSIDE an utterance (between the
%                     digits of a roll number) before DTW.
%   extra.SpeakerCep  [NumFrames x NumSpeakerCep] c1..c12 static cepstrum.
%                     Used by the speaker codebook (vector quantisation).

if nargin < 3 || isempty(cfg), cfg = vsConfig(); end

numCoeffs  = cfg.NumMFCC;
numFilters = cfg.NumMelFilters;
nfft       = cfg.NFFT;
lowFreq    = cfg.MelLowFreq;
highFreq   = min(cfg.MelHighFreq, fs/2);

frameLen  = size(frames, 2);
numUnique = nfft/2 + 1;

% ---- mel filterbank ----
hz2mel = @(f) 2595 * log10(1 + f/700);
mel2hz = @(m) 700 * (10.^(m/2595) - 1);

melPts = linspace(hz2mel(lowFreq), hz2mel(highFreq), numFilters + 2);
hzPts  = mel2hz(melPts);
binPts = min(floor((nfft + 1) * hzPts / fs) + 1, numUnique);

H = zeros(numFilters, numUnique);
for m = 1:numFilters
    fl = binPts(m); fc = binPts(m+1); fr = binPts(m+2);
    if fc > fl
        k = fl:fc;  H(m, k) = (k - fl) / (fc - fl);
    end
    if fr > fc
        k = fc:fr;  H(m, k) = (fr - k) / (fr - fc);
    end
end

% ---- power spectrum -> mel energies -> log -> DCT ----
F         = fft(frames, nfft, 2);
powerSpec = abs(F(:, 1:numUnique)).^2 / frameLen;
melEnergy = powerSpec * H.';
logEnergy = log(max(melEnergy, 1e-12));

D            = vsUtils('dctmtx', numFilters);
fullCepstrum = logEnergy * D.';

if size(fullCepstrum, 2) >= numCoeffs + 1
    staticMFCC = fullCepstrum(:, 2:numCoeffs+1);     % drop c0 energy term
else
    staticMFCC = fullCepstrum(:, 1:min(numCoeffs, end));
end

deltaMFCC      = vsUtils('firdelta', staticMFCC, cfg.DeltaWindow);
deltaDeltaMFCC = vsUtils('firdelta', deltaMFCC,  cfg.DeltaWindow);

switch upper(char(cfg.FeatureDim))
    case '10D', featuresDyn = staticMFCC;
    case '30D', featuresDyn = [staticMFCC, deltaMFCC, deltaDeltaMFCC];
    otherwise,  featuresDyn = [staticMFCC, deltaMFCC];   % 20D default
end

nSpk = min(cfg.NumSpeakerCep, size(fullCepstrum, 2) - 1);
extra = struct();
extra.LogEnergy  = log(sum(melEnergy, 2) + 1e-12);
extra.SpeakerCep = fullCepstrum(:, 2:nSpk+1);
end
