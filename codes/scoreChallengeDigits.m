function r = scoreChallengeDigits(segments, db, verifiedRoll, expected, cfg)
%SCORECHALLENGEDIGITS Recognize each independently segmented digit (0..9).
% Uses this project's ORIGINAL MFCC and normalized DTW for all ten digits,
% considering multiple isolated takes per digit per enrolled speaker.
% Each of the three positions is classified INDEPENDENTLY: there is no
% score boost for the displayed digits. A mismatch or an ambiguous position
% cannot be rescued by other positions or by speaker-model confidence.
if nargin<5 || isempty(cfg), cfg=vsConfig(); end
expected = double(expected(:).');
if numel(expected) ~= 3 || any(expected<0 | expected>9 | expected~=fix(expected))
    error('ParkingSecuritySystem:ExpectedDigits','Expected three digits from 0 to 9.');
end
r = struct('ContentPass',false,'Recognized',nan(1,3), ...
    'RunnerUp',nan(1,3),'Margins',nan(1,3),'Distances',inf(3,10), ...
    'TemplateSpeakers',0,'OwnerTemplate',false,'TemplatesUsed',zeros(3,10), ...
    'Reason','');
if ~iscell(segments) || numel(segments)~=3 || any(cellfun(@isempty,segments))
    r.Reason = 'Cannot recognize digits without three usable segments.';
    return;
end
St = db.Students;
owner = find(strcmp({St.Roll},char(verifiedRoll)),1);
if isempty(owner)
    r.Reason = 'Factor 1 identity does not exist in the enrollment database.';
    return;
end
complete = [];
for k=1:numel(St)
    if isfield(St(k),'Digits') && iscell(St(k).Digits) && ...
            numel(St(k).Digits)==10 && all(cellfun(@(b) iscell(b) && ...
            any(~cellfun(@isempty,b)),St(k).Digits))
        complete(end+1)=k; %#ok<AGROW>
    end
end
if isempty(complete)
    r.Reason = 'No complete 0-9 isolated-digit template bank is enrolled.';
    return;
end
r.OwnerTemplate=ismember(owner,complete);
if r.OwnerTemplate
    pool=[owner,complete(complete~=owner)];
else
    pool=complete;
end
pool=pool(1:min(numel(pool),cfg.ChallengeTemplateSpeakers));
r.TemplateSpeakers=numel(pool);
maxTake=cfg.ChallengeMaxTakesPerDigit;
for p=1:3
    X=double(segments{p});
    if size(X,1)<cfg.ChallengeMinDigitFrames || any(~isfinite(X(:)))
        r.Reason=sprintf('Digit %d has too few clean MFCC frames.',p);
        return;
    end
    for d=0:9
        speakerDist=inf(1,numel(pool));
        for s=1:numel(pool)
            bank=St(pool(s)).Digits{d+1};
            takeDistances=inf(1,min(maxTake,numel(bank)));
            for t=1:numel(takeDistances)
                Y=double(bank{t});
                if isempty(Y) || size(Y,2)~=size(X,2), continue; end
                Y=cmvnNormalize(Y,size(Y,2));
                takeDistances(t)=vsUtils('dtwnorm',X,Y);
                if isfinite(takeDistances(t))
                    r.TemplatesUsed(p,d+1)=r.TemplatesUsed(p,d+1)+1;
                end
            end
            speakerDist(s)=min(takeDistances);
        end
        ordered=sort(speakerDist(isfinite(speakerDist)));
        if isempty(ordered), continue; end
        score=mean(ordered(1:min(cfg.ChallengeBestTemplates,numel(ordered))));
        if r.OwnerTemplate && isfinite(speakerDist(1))
            score=(1-cfg.ChallengeOwnWeight)*score + ...
                cfg.ChallengeOwnWeight*speakerDist(1);
        end
        r.Distances(p,d+1)=score;
    end
    [sorted,order]=sort(r.Distances(p,:));
    if numel(sorted)<2 || ~isfinite(sorted(2))
        r.Reason=sprintf('Not enough reliable digit templates for position %d.',p);
        return;
    end
    r.Recognized(p)=order(1)-1;
    r.RunnerUp(p)=order(2)-1;
    r.Margins(p)=(sorted(2)-sorted(1))/max(sorted(1),1e-9);
end
correct=all(r.Recognized==expected);
confident=all(r.Margins>=cfg.ChallengeDigitMinMargin);
r.ContentPass=correct && confident;
if ~correct
    r.Reason=sprintf('Recognized %s instead of %s.', ...
        strtrim(sprintf('%d ',r.Recognized)),strtrim(sprintf('%d ',expected)));
elseif ~confident
    r.Reason=sprintf('Low digit confidence at position(s) %s.', ...
        strtrim(sprintf('%d ',find(r.Margins<cfg.ChallengeDigitMinMargin))));
else
    r.Reason='All three individual digits matched with sufficient confidence.';
end
end
