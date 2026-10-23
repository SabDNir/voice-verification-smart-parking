function model = trainVerifier(showPlots)
%TRAINVERIFIER  Learn the phrase gate and measure the verifier on held-out data.  [Arnob]
%
% DECISION RULE (verifySpeaker.m, v3.2). A login = roll number + name.
%   claimed student c = argmax over students of the phrase score Sd (DTW)
%   GRANTED iff  G1 Sd(c) >= ThetaPhrase
%                G2 roll number and name both point to c
%                G3 c is the best-matching VOICE of all enrolled students (GMM-UBM)
%                G4 voice LLR(c) >= cfg.VoiceGate
%
% WHAT IS LEARNED HERE
%   ThetaPhrase: a login whose words are not a registered roll number and
%   name must not pass G1. Students are split into cfg.CalibrationFolds
%   groups; each group in turn is removed from the enrolled set and its
%   roll+name recordings are scored as UNREGISTERED speakers. ThetaPhrase is
%   the (1 - cfg.TargetFARUnknown) quantile of their best phrase score.
%
% WHAT IS NOT LEARNED HERE, AND WHY
%   The voice gate comes from vsConfig. Every
%   database take of a student was recorded in one sitting, so a held-out
%   take is far more similar to the rest than a login on another day is:
%   genuine held-out LLRs here are ~0.9-2, but live logins on 27 Sep 2026
%   (same microphone) scored 0.39-1.18. A gate fitted to these numbers
%   would reject most real users. The figures below are still worth
%   reporting: they show how well the models separate students.
%
% HELD-OUT PROTOCOL (no test recording is ever inside its own model)
%   - phrase: a take is never compared with itself
%   - voice : for each genuine test pair (roll_k + name_k) the student's
%             GMM is re-adapted without those two files
%   - unregistered students have no templates and no model in their fold,
%     and the background model of that fold is refitted WITHOUT their
%     speech, so they are scored exactly like a real stranger

if nargin < 1, showPlots = true; end
cfg = vsConfig();
db  = loadDatabase(cfg);
St  = db.Students;
N   = numel(St);
UBM = db.UBM;
MU  = double(db.VoiceMeans);

fprintf('\n=======================================================\n');
fprintf('   TRAINING THE SPEAKER VERIFIER  (%d students)         \n', N);
fprintf('=======================================================\n');

% ---------- test pairs: roll_k + name_k of the same student ----------
P = struct('Spk', {}, 'iRoll', {}, 'iName', {});
for j = 1:N
    u = St(j).Utts;
    r = find(strcmp({u.Utt}, 'roll'));
    for a = r
        b = find(strcmp({u.Utt}, 'name') & [u.Take] == u(a).Take, 1);
        if ~isempty(b), P(end+1) = struct('Spk', j, 'iRoll', a, 'iName', b); end %#ok<AGROW>
    end
end
nP = numel(P);
fprintf('Test logins     : %d (roll number + name pairs)\n', nP);
if nP < 10
    error('ParkingSecuritySystem:TooFewPairs', 'Need roll_NN and name_NN takes with matching numbers.');
end

% ---------- phrase distances (DTW, never against itself) ----------
Dr = inf(nP, N); Dn = inf(nP, N);
t0 = tic;
for p = 1:nP
    j  = P(p).Spk;
    A  = double(St(j).Utts(P(p).iRoll).Content);
    B  = double(St(j).Utts(P(p).iName).Content);
    for i = 1:N
        for t = find(strcmp({St(i).Utts.Utt}, 'roll'))
            if i == j && t == P(p).iRoll, continue; end
            Dr(p, i) = min(Dr(p, i), vsUtils('dtwnorm', A, double(St(i).Utts(t).Content)));
        end
        for t = find(strcmp({St(i).Utts.Utt}, 'name'))
            if i == j && t == P(p).iName, continue; end
            Dn(p, i) = min(Dn(p, i), vsUtils('dtwnorm', B, double(St(i).Utts(t).Content)));
        end
    end
    if mod(p, 15) == 0 || p == nP
        fprintf('   phrase scores %3d / %d   (%.0f s)\n', p, nP, toc(t0));
    end
end

% ---------- voice scores (own model re-adapted without the test pair) ----------
LL = -inf(nP, N);
for p = 1:nP
    j    = P(p).Spk;
    keep = true(1, numel(St(j).Utts)); keep([P(p).iRoll, P(p).iName]) = false;
    M    = MU;
    M(:, :, j) = voiceModel('adapt', double(vertcat(St(j).Utts(keep).Voice)), UBM, cfg.MAPRelevance);
    X    = double([St(j).Utts(P(p).iRoll).Voice; St(j).Utts(P(p).iName).Voice]);
    LL(p, :) = voiceModel('llr', X, M, UBM);
end
fprintf('   voice scores done   (%.0f s)\n', toc(t0));

% ---------- folds of unregistered students ----------
rs    = RandStream('mt19937ar', 'Seed', 312);
perm  = randperm(rs, N);
nF    = min(cfg.CalibrationFolds, N);
folds = arrayfun(@(f) perm(f:nF:end), 1:nF, 'UniformOutput', false);

G = struct('Sd', {}, 'Cons', {}, 'Claim', {}, 'Own', {}, 'LL', {}, 'Rank', {}, 'TopV', {}, 'TopLL', {});
I = G;
nTry = 0;                                    % classmate impersonation attempts
for f = 1:nF
    enr = setdiff(1:N, folds{f});
    Sr  = cohortRatio(Dr, enr, cfg.CohortSize);
    Sn  = cohortRatio(Dn, enr, cfg.CohortSize);
    % background model and voice models without this fold's students
    Se   = St(enr);
    ubmF = voiceModel('trainubm', cell2mat(arrayfun(@(s) double(vertcat(s.Utts.Voice)), Se(:), ...
                      'UniformOutput', false)), cfg);
    MUf  = repmat(ubmF.mu, 1, 1, N);
    for i = enr
        MUf(:, :, i) = voiceModel('adapt', double(vertcat(St(i).Utts.Voice)), ubmF, cfg.MAPRelevance);
    end
    fprintf('   fold %d/%d: %d students unregistered   (%.0f s)\n', f, nF, numel(folds{f}), toc(t0));
    for p = 1:nP
        j  = P(p).Spk;
        sd = (Sr(p, :) + Sn(p, :)) / 2;
        [~, c]  = max(sd);
        [~, cr] = max(Sr(p, :)); [~, cn] = max(Sn(p, :));
        if ismember(j, enr)
            if ~isfinite(sd(j)), continue; end          % student with a single take
            ll = LL(p, :);
        else
            X  = double([St(j).Utts(P(p).iRoll).Voice; St(j).Utts(P(p).iName).Voice]);
            ll = voiceModel('llr', X, MUf, ubmF);
        end
        ll(setdiff(1:N, enr)) = -inf;
        [~, vo] = sort(ll, 'descend');
        e = struct('Sd', sd(c), 'Cons', cr == c && cn == c, 'Claim', c, 'Own', j, ...
                   'LL', ll(c), 'Rank', find(vo == c, 1), 'TopV', vo(1), 'TopLL', ll(vo(1)));
        if ismember(j, enr)
            e.Sd = sd(j);                    % genuine: the student's own scores
            e.LL = ll(j);
            G(end+1) = e; %#ok<AGROW>
            nTry = nTry + numel(enr) - 1;    % this voice claiming each other student
        else
            I(end+1) = e; %#ok<AGROW>
        end
    end
end

% ---------- ThetaPhrase ----------
iSd = [I.Sd];
thetaPhrase = vsUtils('prctile', iSd(isfinite(iSd)), 100 * (1 - cfg.TargetFARUnknown));
thetaPhrase = max(thetaPhrase, 0.01);

% ---------- held-out error rates at these gates ----------
gateOf = @(c) cfg.VoiceGate;
accG = false(1, numel(G)); okG = accG;
for k = 1:numel(G)
    e = G(k);
    accG(k) = e.Sd >= thetaPhrase && e.Cons && e.Claim == e.Own && e.Rank == 1 && e.LL >= gateOf(e.Claim);
    okG(k)  = accG(k);
end
accI = false(1, numel(I)); infI = accI;
for k = 1:numel(I)
    e = I(k);
    accI(k) = e.Sd >= thetaPhrase && e.Cons && e.Rank == 1 && e.LL >= gateOf(e.Claim);
    infI(k) = e.TopLL >= gateOf(e.TopV);      % knows the roll+name of the student they sound most like
end
% a registered classmate saying another student's roll + name: only the
% student whose voice ranks first could be accepted
nWrong = 0;
for k = 1:numel(G)
    e = G(k);
    if e.TopV ~= e.Own && e.TopLL >= gateOf(e.TopV), nWrong = nWrong + 1; end
end

model = struct();
model.ThetaPhrase    = thetaPhrase;
model.CohortSize     = cfg.CohortSize;
model.VoiceGate      = cfg.VoiceGate;
model.FRR            = 1 - mean(okG);
model.FARUnknown     = mean(accI);
model.FARInformed    = mean(infI);
model.FARClassmate   = nWrong / max(nTry, 1);
model.VoiceRank1     = mean([G.Rank] == 1 & [G.Claim] == [G.Own]);
model.PhraseRight    = mean([G.Claim] == [G.Own]);
model.NumGenuine     = numel(G);
model.NumIntruder    = numel(I);
model.NumStudents    = N;
model.GenuineSd      = [G.Sd];
model.IntruderSd     = [I.Sd];
model.GenuineLL      = [G.LL];
model.IntruderTopLL  = [I.TopLL];
model.BuildDate      = datestr(now); %#ok<TNOW1,DATST>
model.Rolls          = {St.Roll};

VerifierModel = model; %#ok<NASGU>
save(cfg.VerifierModelFile, 'VerifierModel');

fprintf('\n-------------------------------------------------------\n');
fprintf('ThetaPhrase (G1, learned)      : %.4f\n', thetaPhrase);
fprintf('Voice gate  (G4, vsConfig)     : %.2f (all students)\n', cfg.VoiceGate);
fprintf('Held-out results on this database (%d genuine logins, %d unregistered):\n', numel(G), numel(I));
fprintf('  Phrase points to the right student      : %5.1f %%\n', 100*model.PhraseRight);
fprintf('  Voice ranks the right student first     : %5.1f %%\n', 100*model.VoiceRank1);
fprintf('  Genuine students rejected (FRR)         : %5.1f %%\n', 100*model.FRR);
fprintf('  Unregistered, saying their own details  : %5.1f %% accepted\n', 100*model.FARUnknown);
fprintf('  Unregistered, saying the details of the : %5.1f %% accepted  (worst case)\n', 100*model.FARInformed);
fprintf('     student whose voice is closest\n');
fprintf('  Registered classmate impersonating      : %5.2f %% of attempts accepted\n', 100*model.FARClassmate);
fprintf('  Genuine voice LLR 5th percentile        : %.2f\n', vsUtils('prctile', model.GenuineLL, 5));
fprintf('Saved to %s\n', cfg.VerifierModelFile);
fprintf(['NOTE: same-session evaluation may overestimate live performance.\n' ...
         '      Same-session estimates may not represent a new microphone.\n']);
fprintf('-------------------------------------------------------\n');

if showPlots
    vsIO('plottraining', model);
end
end


function db = loadDatabase(cfg)
if ~isfile(cfg.DatabaseFile)
    error('ParkingSecuritySystem:NoDatabase', 'No enrolled database. Run ParkingSecuritySystem(''enroll'') first.');
end
db = load(cfg.DatabaseFile);
if ~isfield(db, 'DatabaseVersion') || db.DatabaseVersion < 6 || ~isfield(db, 'UBM')
    error('ParkingSecuritySystem:LegacyDatabase', 'Database is from an older version. Run ParkingSecuritySystem(''enroll'') again.');
end
end
