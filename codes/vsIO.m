function varargout = vsIO(op, varargin)
%VSIO  Capture, microphone checking, reports and simple utility dispatch.
% Microphone recordings are held in memory only.
varargout = {};
switch lower(char(op))
    case 'record'
        [a, fs, info] = recordUtterance(varargin{:});
        varargout = {a, fs, info};
    case 'recordnoise'
        [a, fs, info] = recordAmbientNoise();
        varargout = {a, fs, info};
    case 'listdevices'
        listDevices();
    case 'miccheck'
        micCheck();
    case 'status'
        printStatus();
    case 'help'
        printHelp();
    case 'passstr'
        varargout = {passStr(varargin{:})};
    case 'getarg'
        varargout = {getArg(varargin{:})};
    case 'packout'
        varargout = {packOut(varargin{:})};
    case 'plotverification'
        plotVerification(varargin{:});
    case 'plottraining'
        plotTraining(varargin{:});
    otherwise
        error('ParkingSecuritySystem:BadIO', 'Unknown vsIO operation: %s', char(op));
end
end

function [x, fs, info] = recordAmbientNoise()
% Fixed-length reference taken once per live verification, without VAD.
% It must be recorded using the SAME configured device as roll/name/digits.
% Nothing is written to disk; buildAmbientNoiseProfile performs quality checks.
cfg = vsConfig();
fs = cfg.RecordFs;
x = [];
info = struct('Valid', false, 'Reason', '', 'Seconds', 0);
fprintf('\n=======================================================\n');
fprintf('AMBIENT NOISE: Stay SILENT for %.0f seconds.\n', cfg.AmbientNoiseSeconds);
fprintf('The same noise profile will be used for both factors.\n');
fprintf('=======================================================\n');
try
    rec = audiorecorder(fs, 16, 1, inputDeviceID(cfg));
    fprintf('>>> Capturing background noise now ...\n');
    recordblocking(rec, cfg.AmbientNoiseSeconds);
    x = getaudiodata(rec);
catch ME
    info.Reason = sprintf('Microphone noise capture failed: %s', ME.message);
    fprintf('[AMBIENT] %s\n', info.Reason);
    return;
end
info.Seconds = numel(x) / fs;
info.Valid = info.Seconds >= cfg.AmbientNoiseSeconds - 0.25;
if ~info.Valid
    info.Reason = sprintf('Only %.2f of %.1f seconds recorded.', ...
                          info.Seconds, cfg.AmbientNoiseSeconds);
end
fprintf('>>> ambient captured %.2f s (RAM only)\n', info.Seconds);
end


function [x, fs, info] = recordUtterance(prompt)
% End-pointed recording. Replaces the fixed 3-second clip, which cut off
% 77% of the roll numbers in the database (median 5.3 s of speech).
%
% Short-time energy in 20 ms frames is compared with a noise floor
% measured from the first 0.3 s. Recording stops cfg.EndSilenceSeconds after
% the last speech frame, or at cfg.MaxRecordSeconds.
% v3.3: after speech has started, a frame only counts as speech if it is also
% within cfg.EndRelativeDb of the loudest frame so far. On 28 Sep, people
% talking in the background (30-40 dB below the speaker) kept 7 of the
% day-2 recordings running to the 10 s limit.
cfg = vsConfig();
fs  = cfg.RecordFs;
if nargin < 1, prompt = 'Speak now'; end
info = struct('SpeechFound', false, 'Seconds', 0, 'StoppedBy', '');

rec = audiorecorder(fs, 16, 1, inputDeviceID(cfg));
fprintf('\n>>> %s  [listening - speak when ready]\n', prompt);
record(rec);
t0 = tic;
win = round(0.020 * fs);
started = false; lastVoice = 0; firstVoice = 0; floorDb = [];
while true
    pause(0.1);
    el = toc(t0);
    if rec.TotalSamples < 5 * win
        if el > 3, info.StoppedBy = 'no audio from the microphone'; break; end
        continue;
    end
    y  = getaudiodata(rec);
    n  = floor(numel(y) / win);
    e  = 10 * log10(mean(reshape(y(1:n*win), win, n).^2, 1) + 1e-12);
    if isempty(floorDb) && numel(y) >= 0.3 * fs
        floorDb = vsUtils('prctile', e(1:min(n, 15)), 20);
    end
    % noise floor: the quieter of the first 0.3 s and the quietest 10% so far
    fl = vsUtils('prctile', e, 10);
    if ~isempty(floorDb), fl = min(fl, floorDb); end
    thr = max(fl + cfg.StartMarginDb, cfg.MinSpeechLevelDb);
    act = find(e > thr);
    if started
        % only once at least 0.5 s of strong speech exists, so a click or a
        % breath before the real speech cannot end the recording early
        act2 = find(e > max(thr, max(e) - cfg.EndRelativeDb));
        if numel(act2) >= 25, act = act2; end
    end
    if ~started && numel(act) >= 3
        % at least three 20 ms frames above the threshold = speech onset
        started = true; firstVoice = act(1) * 0.020;
    end
    if started && ~isempty(act), lastVoice = act(end) * 0.020; end
    if started && (numel(y)/fs - lastVoice) >= cfg.EndSilenceSeconds && ...
            (lastVoice - firstVoice) >= cfg.MinSpeechSeconds
        info.StoppedBy = 'end of speech'; break;
    end
    if el >= cfg.MaxRecordSeconds
        info.StoppedBy = 'time limit'; break;
    end
    if ~started && el >= cfg.NoSpeechTimeout
        info.StoppedBy = 'no speech'; break;
    end
end
stop(rec);
if rec.TotalSamples > 0
    x = getaudiodata(rec);
else
    x = zeros(round(0.5 * fs), 1);
end
info.SpeechFound = started;
info.Seconds     = numel(x) / fs;
info.Peak     = max(abs(x));
info.Clipped  = mean(abs(x) >= 0.999);
fprintf('>>> captured %.1f s (%s)\n', info.Seconds, info.StoppedBy);
if info.Clipped > 0.001
    fprintf(['    [!] %.1f%% of the samples are clipped: the input is too loud. Lower the\n' ...
             '        microphone level in Windows (Sound settings > Input > Volume), or\n' ...
             '        stand a little further back. Run MODE = ''mic_check'' to set it.\n'], 100*info.Clipped);
end
end


function micCheck()
% Microphone level check: say your roll number, read the verdict, adjust the
% Windows input volume, repeat until it says GOOD.
listDevices();
fprintf(['\nMICROPHONE LEVEL CHECK\n' ...
         'Stand where you will verify and say your roll number at normal loudness.\n' ...
         'Aim: GOOD. Change the level in Windows: Settings > System > Sound >\n' ...
         'Input > (your microphone) > Volume, then press "Test again".\n']);
while true
    [x, fs, info] = recordUtterance('Mic check: say your roll number');
    if ~info.SpeechFound
        fprintf('   No speech detected. Is the right microphone selected (vsConfig InputDeviceName)?\n');
    else
        w  = round(0.020 * fs); n = floor(numel(x) / w);
        e  = 10 * log10(mean(reshape(x(1:n*w), w, n).^2, 1) + 1e-12);
        pk = 20 * log10(max(abs(x)) + 1e-12);
        fl = vsUtils('prctile', e, 10);
        sp = vsUtils('prctile', e, 95);
        fprintf('   peak %6.1f dBFS | speech %6.1f dBFS | background %6.1f dBFS | SNR %4.0f dB | clipped %.2f%%\n', ...
                pk, sp, fl, sp - fl, 100 * info.Clipped);
        if info.Clipped > 0.001 || pk > -0.5
            v = 'TOO LOUD - lower the Windows input volume (try 10-20 steps lower)';
        elseif pk < -20
            v = 'TOO QUIET - raise the input volume or move closer';
        elseif sp - fl < 20
            v = 'NOISY - the background is close to the speech level; find a quieter spot';
        else
            v = 'GOOD';
        end
        fprintf('   VERDICT: %s\n', v);
    end
    b = questdlg('Microphone level check', 'Mic check', 'Test again', 'Done', 'Test again');
    if ~strcmp(b, 'Test again'), break; end
end
end


function [id, name] = inputDeviceID(cfg)
% Microphone chosen by cfg.InputDeviceName (part of its name), else the
% Windows default. The enrolment recordings and live verification should use
% the same microphone.
id = -1; name = 'Windows default input device';
try
    info = audiodevinfo;
    ins  = info.input;
    if ~isempty(cfg.InputDeviceName) && ~isempty(ins)
        k = find(contains(lower({ins.Name}), lower(cfg.InputDeviceName)), 1);
        if isempty(k)
            warning('ParkingSecuritySystem:NoDevice', 'No input device matches "%s"; using the default.', cfg.InputDeviceName);
        else
            id = ins(k).ID; name = ins(k).Name;
        end
    end
catch
end
end


function listDevices()
cfg = vsConfig();
[~, name] = inputDeviceID(cfg);
fprintf('Microphone in use : %s\n', name);
try
    info = audiodevinfo;
    for k = 1:numel(info.input)
        fprintf('   available input %d: %s\n', info.input(k).ID, info.input(k).Name);
    end
catch
end
end


function plotVerification(report)
if ~isfield(report, 'Order'), return; end
k   = report.Order(1:min(8, numel(report.Order)));
lab = report.Rolls(k);
figure('Name', 'Phase 4: speaker evidence', 'NumberTitle', 'off');
subplot(1, 2, 1);
bar(report.Sd(k)); hold on;
yline(report.ThetaPhrase, '--r', 'gate', 'LineWidth', 1.5);
set(gca, 'XTickLabel', lab, 'XTickLabelRotation', 40);
ylabel('cohort log-ratio'); title('WHAT was said: phrase match (DTW)'); grid on;
subplot(1, 2, 2);
bar(report.Voice(k)); hold on;
yline(report.VoiceGate, '--r', 'gate', 'LineWidth', 1.5);
set(gca, 'XTickLabel', lab, 'XTickLabelRotation', 40);
ylabel('log-likelihood ratio'); title('WHO said it: voice (GMM-UBM)'); grid on;
end


function plotTraining(m)
figure('Name', 'Speaker verifier training', 'NumberTitle', 'off');
subplot(1, 3, 1);
v = m.IntruderSd(isfinite(m.IntruderSd)); g = m.GenuineSd(isfinite(m.GenuineSd));
edges = linspace(min([v, g]), max([v, g]), 40);
histogram(v, edges, 'Normalization', 'probability'); hold on;
histogram(g, edges, 'Normalization', 'probability');
xline(m.ThetaPhrase, '--r', 'LineWidth', 1.5);
legend('unregistered (best match)', 'genuine', 'gate'); xlabel('phrase score S_d');
title('G1 phrase gate'); grid on;

subplot(1, 3, 2);
v = m.IntruderTopLL(isfinite(m.IntruderTopLL)); g = m.GenuineLL(isfinite(m.GenuineLL));
edges = linspace(min([v, g]), max([v, g]), 40);
histogram(v, edges, 'Normalization', 'probability'); hold on;
histogram(g, edges, 'Normalization', 'probability');
xline(m.VoiceGate, '--r', 'LineWidth', 1.5);
legend('unregistered (closest voice)', 'genuine (same sitting)', 'gate');
xlabel('voice log-likelihood ratio'); title('G4 voice gate'); grid on;

subplot(1, 3, 3);
r = 100 * [m.FRR, m.FARUnknown, m.FARInformed, m.FARClassmate];
bar(r); set(gca, 'XTickLabel', {'genuine rejected', 'outsider', 'outsider (informed)', 'classmate'}, ...
             'XTickLabelRotation', 30);
ylabel('%'); title('Held-out error rates (database)'); grid on;
end


function printStatus()
cfg = vsConfig();
fprintf('\n=======================================================\n');
fprintf('             ANTI-THEFT SYSTEM FOR SMART PARKING INFRASTRUCTURE STATUS\n');
fprintf('=======================================================\n');
fprintf('Raw recordings  : %s\n', cfg.RawRecordsDir);
fprintf('Saved models    : %s\n', cfg.DataDir);
if isfile(cfg.DatabaseFile)
    db = load(cfg.DatabaseFile, 'Students', 'BuildDate', 'DatabaseVersion');
    if isfield(db, 'DatabaseVersion') && db.DatabaseVersion >= 5
        fprintf('Enrolled        : %d students (built %s)\n', numel(db.Students), db.BuildDate);
    else
        fprintf('Enrolled        : older format; run ParkingSecuritySystem(''enroll'')\n');
    end
else
    fprintf('Enrolled        : none\n');
end
if isfile(cfg.VerifierModelFile)
    tmp = load(cfg.VerifierModelFile, 'VerifierModel');
    m = tmp.VerifierModel;
    fprintf('Verifier        : trained %s; same-session FRR %.1f%%\n', ...
            m.BuildDate, 100*m.FRR);
else
    fprintf('Verifier        : not trained\n');
end
fprintf('Voice threshold : %.2f\n', cfg.VoiceGate);
fprintf('Factor 1        : enter ID + roll/name four gates; verified ID must match entered ID\n');
fprintf('Factor 2        : random %d digits 0-9 + dedicated digit-only GMM-UBM\n', cfg.ChallengeLength);
if isfile(cfg.DigitVoiceModelFile)
    try
        tmpD = load(cfg.DigitVoiceModelFile,'DigitVoiceModel');
        fprintf('Digit-only model: %d eligible students (trained %s)\n', ...
            numel(tmpD.DigitVoiceModel.Rolls),tmpD.DigitVoiceModel.BuildDate);
    catch
        fprintf('Digit-only model: unreadable; run ENROLL_STUDENTS.m\n');
    end
else
    fprintf('Digit-only model: missing; run ENROLL_STUDENTS.m\n');
end
fprintf('Digit matching  : segmented MFCC/DTW, margin %.1f%% per digit\n', ...
        100*cfg.ChallengeDigitMinMargin);
fprintf('Challenge voice : baseline %.2f, or per-student LIVE calibration\n', ...
        cfg.ChallengeVoiceGate);
if cfg.UseAmbientNoiseReference && cfg.SpectralSubtraction
    fprintf('Noise reduction : one %.0f-s ambient recording per live login\n', ...
            cfg.AmbientNoiseSeconds);
    fprintf('Noise fallback  : quietest-frame estimator if invalid\n');
else
    fprintf('Noise reduction : per-recording spectral subtraction\n');
end
fprintf('Recording       : temporary RAM only, no capture files\n');
fprintf('=======================================================\n');
end

function s = passStr(v)
if v, s = 'PASS'; else, s = 'FAIL'; end
end


function out = packOut(vals, n)
out = vals(1:min(max(n, 0), numel(vals)));
end


function v = getArg(args, idx, dflt)
if numel(args) >= idx && ~isempty(args{idx})
    v = args{idx};
else
    v = dflt;
end
end


function printHelp()
fprintf([ ...
'\nANTI-THEFT SYSTEM FOR SMART PARKING INFRASTRUCTURE: enrollment + two-factor voice verification\n' ...
'Run ENROLL_STUDENTS.m to enroll/train. Run RUN_ME.m for live verification.\n' ...
'Commands:\n' ...
'  ParkingSecuritySystem(''enroll'')    build database from offline recordings\n' ...
'  ParkingSecuritySystem(''train'')     learn phrase gate; evaluate\n' ...
'  ParkingSecuritySystem(''status'')    print current status\n' ...
'  ParkingSecuritySystem(''verify'')    record roll + name, then random 3 digits\n' ...
'  ParkingSecuritySystem(''verifyfiles'', rollWav, nameWav, challengeWav, [d1 d2 d3])\n\n']);
end
