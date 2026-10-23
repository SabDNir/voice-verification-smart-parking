function model = trainDigitVoiceModel(cfg)
%TRAINDIGITVOICEMODEL Independent Factor 2 GMM-UBM, using ONLY isolated digits.
% Uses the unchanged voiceModel.m training/adaptation routines and the
% digit-only voice features already extracted from raw_records/ by enrollment.
% No live audio is collected or stored here.  Factor 1 models are untouched.
if nargin < 1 || isempty(cfg), cfg = vsConfig(); end
if ~isfile(cfg.DatabaseFile)
    error('ParkingSecuritySystem:NoDatabase', ...
        'Run ENROLL_STUDENTS.m to build EnrolledDatabase.mat first.');
end
db = load(cfg.DatabaseFile);
if ~isfield(db,'Students') || ~isfield(db,'BuildDate') || ...
        ~isfield(db,'DatabaseVersion') || db.DatabaseVersion < 6
    error('ParkingSecuritySystem:DigitVoiceInput', ...
        'Enrollment database does not contain the required isolated-digit utterances.');
end
words = {'zero','one','two','three','four','five','six','seven','eight','nine'};
expectedDim = 2*cfg.NumSpeakerCep;
rolls = {};
indices = [];
frameSets = {};
frameCounts = [];
skipped = {};
fprintf('\n=======================================================\n');
fprintf('    FACTOR 2 - TRAIN DIGIT-ONLY GMM-UBM\n');
fprintf('    Source: isolated digit recordings in enrolled raw_records\n');
fprintf('=======================================================\n');
for k = 1:numel(db.Students)
    s = db.Students(k);
    pieces = cell(1,10);
    valid = true;
    if ~isfield(s,'Utts') || isempty(s.Utts)
        valid = false;
    else
        uttNames = {s.Utts.Utt};
        for d = 1:10
            matches = find(strcmp(uttNames,words{d}));
            matches = matches(1:min(numel(matches),cfg.DigitVoiceMaxTakesPerDigit));
            takes = {};
            for j = matches
                x = double(s.Utts(j).Voice);
                if size(x,1)>=cfg.DigitVoiceMinFramesPerDigit && ...
                        size(x,2)==expectedDim && all(isfinite(x(:)))
                    takes{end+1} = x; %#ok<AGROW>
                end
            end
            if isempty(takes)
                valid = false;
                break;
            end
            pieces{d} = vertcat(takes{:});
        end
    end
    if ~valid
        skipped{end+1} = sprintf('%s (missing/short isolated digits)',s.Roll); %#ok<AGROW>
        continue;
    end
    X = vertcat(pieces{:});
    if size(X,1) > cfg.DigitVoiceFramesPerStudent
        X = X(round(linspace(1,size(X,1),cfg.DigitVoiceFramesPerStudent)),:);
    end
    if size(X,1) < cfg.DigitVoiceMinFramesPerStudent
        skipped{end+1} = sprintf('%s (insufficient digit speech frames)',s.Roll); %#ok<AGROW>
        continue;
    end
    rolls{end+1} = s.Roll; %#ok<AGROW>
    indices(end+1) = k; %#ok<AGROW>
    frameSets{end+1} = X; %#ok<AGROW>
    frameCounts(end+1) = size(X,1); %#ok<AGROW>
    fprintf('  %s : 10/10 digits, %d balanced voice frames\n',s.Roll,size(X,1));
end
if numel(indices) < 2
    error('ParkingSecuritySystem:DigitVoiceCoverage', ...
        ['At least two students need ALL 10 valid isolated digits. ' ...
         'Add the missing recordings to raw_records/ and re-enroll.']);
end
Xall = vertcat(frameSets{:});
% Reuse EXACTLY the original GMM-UBM training and MAP-adaptation algorithms.
ubm = voiceModel('trainubm',Xall,cfg);
mu = zeros(ubm.K,size(ubm.mu,2),numel(indices),'single');
for i = 1:numel(indices)
    mu(:,:,i) = single(voiceModel('adapt',frameSets{i},ubm,cfg.MAPRelevance));
end
model = struct();
model.ModelVersion = 1;
model.BuildDate = datestr(now);
model.BuildTimestamp = now;  % invalidates calibrations whenever retrained
model.SourceDatabaseBuildDate = db.BuildDate;
model.SourceDatabaseVersion = db.DatabaseVersion;
model.SourcePipelineVersion = cfg.PipelineVersion;
model.StudentRollsAtTraining = {db.Students.Roll};
model.Rolls = rolls;
model.StudentIndices = indices;
model.UBM = ubm;
model.VoiceMeans = mu;
model.FrameCounts = frameCounts;
model.Parameters = digitVoiceParameters(cfg);
DigitVoiceModel = model; %#ok<NASGU>
if ~isfolder(cfg.DataDir), mkdir(cfg.DataDir); end
save(cfg.DigitVoiceModelFile,'DigitVoiceModel','-v7.3');
fprintf('Trained %d digit-only speaker models from %d balanced frames.\n', ...
    numel(indices),size(Xall,1));
fprintf('Saved separately: %s\n',cfg.DigitVoiceModelFile);
if ~isempty(skipped)
    fprintf('[NO DIGIT-VOICE MODEL] %s\n',strjoin(skipped,'; '));
    fprintf(['Those students remain enrolled for Factor 1, but cannot pass ' ...
             'Factor 2 until all ten isolated digits are enrolled.\n']);
end
end
