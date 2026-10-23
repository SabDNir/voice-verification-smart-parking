function [granted, identity, report] = verifySpeaker(U, db, model, cfg, verbose, deferAccess)
%VERIFYSPEAKER  Phase 4 - whose login is this, and is it really them?  [Arnob]
%
%   U is one utterance or a struct array of the utterances of one login
%   (by default the roll number and then the name, see cfg.LoginSequence).
%
%   TWO QUESTIONS, TWO KINDS OF EVIDENCE (v3.2)
%   1. WHAT was said -> who is being claimed.
%        Sd(c) = DTW against student c's own takes of the same phrase,
%                cohort-normalised, averaged over roll number and name.
%        The claimed student is the one with the highest Sd. (27 Sep live
%        test: right in 36 of 36 utterances, impersonators included.)
%   2. WHO is speaking -> is it really the claimed student?
%        LLR(c) = GMM-UBM log-likelihood ratio of all speech frames against
%                 student c's voice model (voiceModel.m).
%
%   GRANTED only if every gate passes for the claimed student c:
%     G1  phrase      Sd(c) >= ThetaPhrase   a registered roll number and name were said
%     G2  consistent  roll number and name point to the same student
%     G3  voice rank  c is the BEST-matching voice of all enrolled students
%     G4  voice level LLR(c) >= voice gate
%
%   G3 is what stops a classmate who says your roll number and name: their
%   own voice model matches them better than yours does. G4 stops someone
%   who is not enrolled at all (they have no model of their own to win G3).

if numel(U) ~= 2 || ~all(strcmp({U.UttType}, {'roll', 'name'}))
    error('ParkingSecuritySystem:TwoPhrases', 'Authentication requires roll number AND full name.');
end
if nargin < 4 || isempty(cfg), cfg = vsConfig(); end
if nargin < 5, verbose = true; end
if nargin < 6, deferAccess = false; end

St = db.Students;
N  = numel(St);
tP = model.ThetaPhrase;
gate = cfg.VoiceGate;
src = 'trained phrase threshold + configured speaker threshold';

dD     = speakerDistances(U, St);
nU     = size(dD, 1);
SdEach = cohortRatio(dD, 1:N, model.CohortSize);      % [nU x N]
Sd     = mean(SdEach, 1);

X = [];
for k = 1:numel(U)
    X = [X; voiceModel('features', U(k).VQ)]; %#ok<AGROW>
end
llr = voiceModel('llr', X, db.VoiceMeans, db.UBM);

[~, order]  = sort(Sd, 'descend');
c           = order(1);
[~, topEach] = max(SdEach, [], 2);
[~, vorder] = sort(llr, 'descend');
vrank       = find(vorder == c, 1);

g = struct('G1_Phrase',     Sd(c) >= tP, ...
           'G2_Consistent', all(topEach == c) || nU < 2, ...
           'G3_VoiceRank',  vrank == 1, ...
           'G4_VoiceLevel', llr(c) >= gate);
granted = g.G1_Phrase && g.G2_Consistent && g.G3_VoiceRank && g.G4_VoiceLevel;

identity = 'REJECTED';
if granted
    identity = St(c).Roll;
    reason = 'All gates passed.';
else
    % Keep the GUI denial message concise when another enrolled speaker is
    % a better voice match. The detailed gate diagnostics remain available
    % in the command-window report below.
    if ~g.G3_VoiceRank
        reason = sprintf('Claimed student %s; the voice matches %s better', ...
                         St(c).Roll, St(vorder(1)).Roll);
    else
        f = {};
        if ~g.G1_Phrase,     f{end+1} = sprintf('phrase match %.3f below %.3f', Sd(c), tP); end
        if ~g.G2_Consistent, f{end+1} = 'roll number and name point to different students'; end
        if ~g.G4_VoiceLevel, f{end+1} = sprintf('voice score %.2f below %.2f', llr(c), gate); end
        reason = sprintf('Claimed student %s: %s.', St(c).Roll, strjoin(f, '; '));
    end
end

report = struct();
report.Reason       = reason;
report.Gates        = g;
report.BestRoll     = St(c).Roll;
report.BestName     = St(c).Name;
report.Sd           = Sd;
report.SdEach       = SdEach;
report.Voice        = llr;
report.VoiceRank    = vrank;
report.VoiceOrder   = vorder;
report.Order        = order;
report.Rolls        = {St.Roll};
report.ThetaPhrase  = tP;
report.VoiceGate    = gate;
report.Thresholds   = src;
report.Duration     = sum([U.Duration]);

if verbose
    L = repmat('-', 1, 72);
    fprintf('\n%s\n              SPEAKER VERIFICATION REPORT (PHASE 4)\n%s\n', L, L);
    fprintf('Utterances: %s   (%.1f s of speech)   gates: %s\n', ...
            strjoin({U.UttType}, ' + '), report.Duration, src);
    fprintf('%-10s %8s %11s %6s\n', 'Roll', 'Phrase', 'Voice LLR', 'rank');
    show = unique([order(1:min(5, N)), vorder(1)], 'stable');
    for k = show
        fprintf('%-10s %8.3f %11.2f %6d\n', St(k).Roll, ...
                Sd(k), llr(k), find(vorder == k, 1));
    end
    fprintf('Claimed %s: phrase >= %.3f, voice rank 1, voice >= %.2f\n', St(c).Roll, tP, gate);
    fprintf('Gates: G1 phrase %s | G2 consistent %s | G3 voice rank %s | G4 voice level %s\n', ...
            vsIO('passstr', g.G1_Phrase), vsIO('passstr', g.G2_Consistent), ...
            vsIO('passstr', g.G3_VoiceRank), vsIO('passstr', g.G4_VoiceLevel));
    if granted
        if deferAccess
            fprintf('DECISION : FACTOR 1 PASSED  ->  %s (three-digit challenge required)\n', St(c).Roll);
        else
            fprintf('DECISION : ACCESS GRANTED  ->  %s\n', St(c).Roll);
        end
    else
        fprintf('DECISION : ACCESS DENIED\nREASON   : %s\n', reason);
    end
    fprintf('%s\n', L);
end
end


function s = shorten(s, n)
if numel(s) > n, s = [s(1:n-1) '.']; end
end
