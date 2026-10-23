function db = enrollTemplates(rawRecordsDir, outputMatFile)
%ENROLLTEMPLATES  Build phrase templates and GMM-UBM speaker models.
% Expected per-student filename: 1234567_roll_01.wav, 1234567_name_01.wav
% Additional roll/name and isolated digit takes are loaded automatically.
% Digit words zero..nine are retained as MFCC templates for the new challenge
% as well as contributing speech to the unchanged GMM-UBM model.

cfg = vsConfig();
if nargin < 1 || isempty(rawRecordsDir), rawRecordsDir = cfg.RawRecordsDir; end
if nargin < 2 || isempty(outputMatFile), outputMatFile = cfg.DatabaseFile; end
rawRecordsDir = char(rawRecordsDir);
if ~exist(cfg.DataDir, 'dir'), mkdir(cfg.DataDir); end

fprintf('\n=======================================================\n');
fprintf('    ENROLLING STUDENTS  (voice authentication)            \n');
fprintf('=======================================================\n');
fprintf('Raw recordings : %s\n', rawRecordsDir);

if ~exist(rawRecordsDir, 'dir')
    error('ParkingSecuritySystem:NoDir', 'raw_records directory "%s" not found.', rawRecordsDir);
end

names = readSpeakerNames(cfg.SpeakersFile);

items    = dir(rawRecordsDir);
dirNames = {items([items.isdir]).name};
dirNames = sort(dirNames(~ismember(dirNames, {'.', '..'})));

digitWords = {'zero','one','two','three','four','five','six','seven','eight','nine'};
Students   = struct('Roll', {}, 'Name', {}, 'Folder', {}, 'Utts', {}, ...
                    'Digits', {}, 'F0Median', {}, 'NumFiles', {});
skipped    = {};

for i = 1:numel(dirNames)
    sdir  = fullfile(rawRecordsDir, dirNames{i});
    files = [dir(fullfile(sdir, '*.wav')); dir(fullfile(sdir, '*.m4a'))];
    if isempty(files)
        skipped{end+1} = sprintf('%s (empty folder)', dirNames{i}); %#ok<AGROW>
        continue;
    end

    utts = struct('Utt', {}, 'Take', {}, 'File', {}, 'Content', {}, ...
                  'DigitSeg', {}, 'Voice', {}, 'Duration', {});
    roll = '';
    f0s  = [];
    for j = 1:numel(files)
        tok = regexp(files(j).name, '^(\d{7})_([A-Za-z]+)_(\d{1,3})\.(wav|m4a)$', 'tokens', 'once', 'ignorecase');
        if isempty(tok)
            fprintf('   [!] %s/%s ignored: name does not follow <roll>_<utterance>_<take>.wav\n', ...
                    dirNames{i}, files(j).name);
            continue;
        end
        if isempty(roll), roll = tok{1}; end
        if ~strcmp(roll, tok{1})
            fprintf('   [!] %s/%s ignored: roll %s differs from %s\n', dirNames{i}, files(j).name, tok{1}, roll);
            continue;
        end
        fp = fullfile(sdir, files(j).name);
        try
            [a, fsIn] = audioread(fp);
        catch ME
            fprintf('   [!] %s could not be read (%s). Convert it to PCM WAV.\n', files(j).name, ME.message);
            continue;
        end
        U = analyzeUtterance(a, fsIn, cfg);
        take = str2double(tok{3});
        phrase = [];
        if ismember(lower(tok{2}), {'roll', 'name'}), phrase = single(U.Content); end
        digitSeg = [];
        if ismember(lower(tok{2}), digitWords) && ~U.IsSilent && ...
                size(U.DigitSeg,1) >= 8 && all(isfinite(U.DigitSeg(:)))
            digitSeg = single(U.DigitSeg);
        end
        u = struct('Utt', lower(tok{2}), 'Take', take, 'File', fp, ...
                   'Content', phrase, 'DigitSeg', digitSeg, ...
                   'Voice', single(voiceModel('features', U.VQ)), ...
                   'Duration', U.Duration);
        utts(end+1) = u; %#ok<AGROW>
        cue = speakerFeatures(U.Clean, U.StaticMFCC, U.Fs8);
        if cue.Valid, f0s(end+1) = cue.F0Median; end %#ok<AGROW>
    end

    if isempty(utts)
        skipped{end+1} = sprintf('%s (no readable, correctly named files)', dirNames{i}); %#ok<AGROW>
        continue;
    end

    if ~any(strcmp({utts.Utt}, 'roll')) || ~any(strcmp({utts.Utt}, 'name'))
        skipped{end+1} = sprintf('%s (needs roll and name recordings)', dirNames{i}); %#ok<AGROW>
        continue;
    end

    % Digits{d+1} is a cell array of *all* usable isolated takes of digit d.
    digits = cell(1, 10);
    for d = 1:10
        matching = find(strcmp({utts.Utt}, digitWords{d}));
        digits{d} = arrayfun(@(t) double(t.DigitSeg), utts(matching), 'UniformOutput', false);
        digits{d} = digits{d}(~cellfun(@isempty, digits{d}));
    end

    nm = '';
    if isKey(names, roll), nm = names(roll); end

    s = struct('Roll', roll, 'Name', nm, 'Folder', sdir, 'Utts', utts, ...
               'Digits', {digits}, ...
               'F0Median', median(f0s), ...
               'NumFiles', numel(utts));
    Students(end+1) = s; %#ok<AGROW>

    nRoll  = sum(strcmp({utts.Utt}, 'roll'));
    nName = sum(strcmp({utts.Utt}, 'name'));
    fprintf('  %s  files %2d | roll %d | name %d | digits %d/10 | %5.1f s speech | F0 %3.0f Hz\n', ...
            roll, numel(utts), nRoll, nName, nnz(~cellfun(@isempty, digits)), ...
            sum(cellfun(@(u) size(u,1), {utts.Voice})) * cfg.FrameLengthMs*(1-cfg.OverlapRatio)/1000, ...
            median(f0s));
end

if isempty(Students)
    error('ParkingSecuritySystem:Empty', 'Enrolment failed - no student folder produced usable recordings.');
end

% ---------- GMM-UBM voice models ----------
fprintf('\nTraining the voice models (GMM-UBM, %d mixtures) ...\n', cfg.NumMixtures);
t0  = tic;
Xall = cell2mat(arrayfun(@(s) double(vertcat(s.Utts.Voice)), Students(:), 'UniformOutput', false));
UBM  = voiceModel('trainubm', Xall, cfg);
clear Xall
VoiceMeans = zeros(UBM.K, size(UBM.mu, 2), numel(Students), 'single');
for k = 1:numel(Students)
    VoiceMeans(:, :, k) = single(voiceModel('adapt', double(vertcat(Students(k).Utts.Voice)), UBM, cfg.MAPRelevance));
end
fprintf('   UBM from %d frames, %d student models, %.0f s\n', UBM.NumFrames, numel(Students), toc(t0));

DatabaseVersion = 6; %#ok<NASGU>
BuildDate       = datestr(now); %#ok<NASGU,TNOW1,DATST>
ConfigUsed      = cfg; %#ok<NASGU>
save(outputMatFile, 'Students', 'UBM', 'VoiceMeans', 'DatabaseVersion', 'BuildDate', 'ConfigUsed');

fprintf('\n-------------------------------------------------------\n');
fprintf('Enrolled %d students. Saved to %s\n', numel(Students), outputMatFile);
if ~isempty(skipped)
    fprintf('Skipped  : %s\n', strjoin(skipped, '; '));
end
for k = 1:numel(Students)
    nr = sum(strcmp({Students(k).Utts.Utt}, 'roll'));
    if nr < 2
        fprintf('[WARNING] %s has %d roll take(s). Add more prerecorded roll/name takes to raw_records/.\n', ...
                Students(k).Roll, nr);
    end
    nDigits = nnz(~cellfun(@isempty, Students(k).Digits));
    if nDigits < 10
        fprintf('[NOTE] %s has %d/10 usable isolated digits. Factor 2 uses other students'' digit templates if needed.\n', ...
                Students(k).Roll, nDigits);
    end
end
fprintf('Next: ParkingSecuritySystem(''train'') to learn the verification threshold.\n');
fprintf('-------------------------------------------------------\n');

if nargout > 0
    db = struct('Students', Students, 'UBM', UBM, 'VoiceMeans', VoiceMeans, 'DatabaseVersion', 6);
end
end


function m = readSpeakerNames(fname)
m = containers.Map('KeyType', 'char', 'ValueType', 'char');
if ~isfile(fname), return; end
try
    T = readtable(fname, 'TextType', 'string', 'Delimiter', ',');
    if ~all(ismember({'Roll', 'Name'}, T.Properties.VariableNames)), return; end
    for r = 1:height(T)
        key = strtrim(char(string(T.Roll(r))));
        if numel(key) == 3, key = ['2206' key]; end
        val = T.Name(r);
        if ismissing(val), val = ""; end
        m(key) = strtrim(char(val));
    end
catch
end
end
