classdef ParkingSecuritySystemApp < matlab.apps.AppBase
%PARKINGSECURITYSYSTEMAPP Group 04 visual layout with the full backend.
% No Group 04 enrollment, features, filters, speaker scores, digit matching,
% thresholds, or microphone recording routines are used here. Every decision
% comes from ParkingSecuritySystem('verifygui', ID, callbacks) alone.
% Native RUN_ME_COMMAND_WINDOW.m retains the original command-line behavior.

    properties (Access = public)
        UIFigure         matlab.ui.Figure
        TitleLabel       matlab.ui.control.Label
        EnrolledLabel    matlab.ui.control.Label
        ClaimIDLabel     matlab.ui.control.Label
        ClaimIDField     matlab.ui.control.EditField
        StepLabel        matlab.ui.control.Label
        PromptLabel      matlab.ui.control.Label
        HintLabel        matlab.ui.control.Label
        StatusLabel      matlab.ui.control.Label
        LiveHeadingLabel matlab.ui.control.Label
        DoneButton       matlab.ui.control.Button
        TimerLabel       matlab.ui.control.Label
        StartButton      matlab.ui.control.Button

        NameWaveformAxes      matlab.ui.control.UIAxes
        NameSpectrumAxes      matlab.ui.control.UIAxes
        IDWaveformAxes        matlab.ui.control.UIAxes
        IDSpectrumAxes        matlab.ui.control.UIAxes
        ChallengeWaveformAxes matlab.ui.control.UIAxes
        ChallengeSpectrumAxes matlab.ui.control.UIAxes
        NameStateLabel        matlab.ui.control.Label
        IDStateLabel          matlab.ui.control.Label
        ChallengeStateLabel   matlab.ui.control.Label

        DecisionLabel    matlab.ui.control.Label
        IdentityLabel    matlab.ui.control.Label
        DetailLabel      matlab.ui.control.Label
        AuditArea        matlab.ui.control.TextArea
        ScoreLabel       matlab.ui.control.Label

        ToleranceSlider  matlab.ui.control.Slider
        ToleranceLabel   matlab.ui.control.Label
        SpoofSlider      matlab.ui.control.Slider
        SpoofLabel       matlab.ui.control.Label
    end

    properties (Access = private)
        Cfg
        ActiveStep = 0
        BaseFigureSize = [1 1]
        IsVerifying = false
        ClaimedID = ''
        Factor1Info = struct()
        Factor2Info = struct()
        Factor1Passed = false
        Factor2Seen = false
        ExpectedDigits = []
    end

    methods (Access = private)
        function startupFcn(app)
            app.Cfg = vsConfig();
            app.ActiveStep = 0;
            app.resetStepStates();
            app.clearAllSignalAxes();
            app.StepLabel.Text = '';
            app.PromptLabel.Text = 'Enter a Student ID and press START VERIFICATION';
            app.HintLabel.Text = '';
            app.StatusLabel.Text = '';
            app.TimerLabel.Text = '';
            app.DoneButton.Visible = 'off'; % Automatic speech endpointing is enabled.
            app.setDecision('READY',[0.14 0.14 0.16],'', ...
                'Factor 1: roll + name  |  Factor 2: three digits + same speaker');
            app.setAudit({'Waiting for verification to begin.'});
            app.refreshDatabase();
        end

        function refreshDatabase(app)
            % Read only the original persistent enrollment/models.
            try
                checkModelsReady(app.Cfg);
                ready=checkDigitVoiceReady(app.Cfg);
                s=load(app.Cfg.DatabaseFile,'Students');
                n=numel(s.Students);
                app.EnrolledLabel.Text=sprintf( ...
                    '%d enrolled  |  %d eligible for Factor 2', ...
                    n,numel(ready.Rolls));
                app.EnrolledLabel.FontColor=[0.35 0.35 0.35];
                app.StartButton.Enable='on';
            catch ME
                app.StartButton.Enable='off';
                app.EnrolledLabel.Text='Models missing/incompatible - run ENROLL_STUDENTS.m';
                app.EnrolledLabel.FontColor=[0.75 0.35 0];
                app.setDecision('MODEL ERROR',[0.78 0.08 0.08],'',ME.message);
                app.setAudit({ME.message});
                fprintf(2,'[GUI] Startup model check: %s\n',ME.message);
            end
        end

        function DoneButtonPushed(app, ~)
            % Kept solely for compatibility with Group 04's GUI component.
            % The endpointed recorder automatically stops at silence.
            app.setStatus('Recording ends automatically after silence.',[0.08 0.29 0.63]);
        end

        function StartButtonPushed(app, ~)
            if app.IsVerifying, return; end
            claim=strtrim(char(app.ClaimIDField.Value));
            if isempty(regexp(claim,'^\d{7}$','once'))
                app.setDecision('INVALID ID',[0.78 0.08 0.08],'', ...
                    'Enter your complete seven-digit student ID.');
                app.setAudit({'Claim must contain exactly seven digits.'});
                return;
            end
            app.IsVerifying=true;
            app.StartButton.Enable='off';
            app.ClaimIDField.Enable='off';
            app.ClaimedID=claim;
            app.ActiveStep=0;
            app.Factor1Info=struct();
            app.Factor2Info=struct();
            app.Factor1Passed=false;
            app.Factor2Seen=false;
            app.ExpectedDigits=[];
            app.resetStepStates();
            app.clearAllSignalAxes();
            app.setDecision('VERIFICATION RUNNING',[0.08 0.29 0.63], ...
                sprintf('Claimed ID: %s',claim), ...
                'Both verification factors are mandatory.');
            app.updateAudit();
            drawnow;
            unlock=onCleanup(@()app.unlockUI()); %#ok<NASGU>
            % Read-only callbacks: the GUI cannot override backend scoring.
            hooks=struct( ...
                'OnPrompt',@(stage,expected)app.onPrompt(stage,expected), ...
                'OnAudio',@(stage,x,fs)app.onAudio(stage,x,fs), ...
                'OnFactor1',@(passed,speaker,info,claimed) ...
                    app.onFactor1(passed,speaker,info,claimed), ...
                'OnChallenge',@(digits)app.onChallenge(digits), ...
                'OnFactor2',@(passed,info)app.onFactor2(passed,info), ...
                'OnNotice',@(stage,reason)app.onNotice(stage,reason));
            try
                % Native engine prints ALL original verbose reports to the
                % MATLAB Command Window. No output is redirected/suppressed.
                [ok,speaker,report]=ParkingSecuritySystem('verifygui',claim,hooks);
                app.renderFinal(ok,speaker,report);
                if ok
                    fprintf('\nRESULT: ACCESS GRANTED  (%s)\n',speaker);
                else
                    fprintf('\nRESULT: ACCESS DENIED   (%s)\n',report.Reason);
                end
            catch ME
                fprintf(2,'\n[GUI] LIVE VERIFICATION ERROR:\n%s\n',getReport(ME,'extended'));
                app.setDecision('VERIFICATION ERROR',[0.78 0.08 0.08], ...
                    sprintf('Claimed ID: %s',claim),ME.message);
                app.setStatus('Check detailed error in Command Window.',[0.78 0.08 0.08]);
                app.setAudit({sprintf('Claimed ID: %s',claim),ME.message});
            end
        end

        function unlockUI(app)
            if ~isvalid(app), return; end
            app.IsVerifying=false;
            if isgraphics(app.UIFigure)
                app.StartButton.Enable='on';
                app.ClaimIDField.Enable='on';
                app.DoneButton.Visible='off';
                app.TimerLabel.Text='';
                drawnow;
            end
        end

        function onPrompt(app,stage,expected)
            if ~isgraphics(app.UIFigure), return; end
            amber=[0.75 0.50 0];
            switch lower(char(stage))
                case 'noise'
                    app.ActiveStep=0;
                    app.setPrompt('AMBIENT REFERENCE', ...
                        'Stay silent for 3 seconds', ...
                        'Same reference is shared by both factors.',amber);
                    app.setStatus('Recording shared noise reference...',amber);
                    app.TimerLabel.Text='3 seconds';
                case 'roll'
                    app.ActiveStep=2; % The student-ID signal panel is displayed first.
                    app.setStepState(2,'Recording',amber);
                    app.setPrompt('FACTOR 1   |   ROLL / ID', ...
                        'Say your full student ID', ...
                        'Recording stops automatically after silence.',amber);
                    app.setStatus('Listening for roll number...',amber);
                    app.TimerLabel.Text='Auto-stop';
                case 'name'
                    app.ActiveStep=1;
                    app.setStepState(1,'Recording',amber);
                    app.setPrompt('FACTOR 1   |   NAME', ...
                        'Say your full name', ...
                        'Recording stops automatically after silence.',amber);
                    app.setStatus('Listening for full name...',amber);
                    app.TimerLabel.Text='Auto-stop';
                case 'challenge'
                    app.ActiveStep=3;
                    app.setStepState(3,'Recording',amber);
                    app.setPrompt('FACTOR 2   |   3-DIGIT CHALLENGE', ...
                        ['SAY  ',app.digitsAsText(expected)], ...
                        'Pause 0.25-0.50 s between digits.',[0.08 0.29 0.63]);
                    app.setStatus('Listening for three digits and the same speaker...',amber);
                    app.TimerLabel.Text='Auto-stop';
            end
            drawnow;
        end

        function onAudio(app,stage,x,fs)
            if ~isgraphics(app.UIFigure), return; end
            if strcmpi(stage,'noise')
                app.setStatus('Ambient reference captured; processing audio.', ...
                    [0.08 0.29 0.63]);
                app.TimerLabel.Text='';
                return;
            end
            if isempty(x) || ~isscalar(fs) || fs<=0
                app.TimerLabel.Text='No usable recording';
                return;
            end
            % All project recordings use cfg.RecordFs. For an unexpected
            % different device rate, skip visualization, NOT authentication.
            if fs==app.Cfg.RecordFs
                app.showWaveform(x,'');
                app.showSpectrum(x,'');
            end
            app.TimerLabel.Text=sprintf('Captured %.1f s',numel(x)/fs);
            app.setStepState(app.ActiveStep,'Checking',[0.08 0.29 0.63]);
            app.setStatus('Authenticating speaker and spoken content...', [0.08 0.29 0.63]);
        end

        function onFactor1(app,passed,speaker,info,~)
            if ~isgraphics(app.UIFigure), return; end
            app.Factor1Info=info;
            app.Factor1Passed=logical(passed);
            cpass=[0.05 0.48 0.28]; cfail=[0.78 0.08 0.08];
            if passed
                app.setStepState(1,'Passed',cpass);
                app.setStepState(2,'Passed',cpass);
                app.setDecision('FACTOR 1 PASSED',cpass, ...
                    sprintf('Claimed: %s   |   Verified speaker: %s',app.ClaimedID,speaker), ...
                    'Proceed to the three-digit challenge. Access is NOT granted yet.');
                app.setStatus('Factor 1 passed. Factor 2 is mandatory.',cpass);
            else
                app.setStepState(1,'Failed',cfail);
                app.setStepState(2,'Failed',cfail);
                app.setDecision('FACTOR 1 FAILED',cfail, ...
                    sprintf('Claimed: %s   |   Verified speaker: NOT VERIFIED',app.ClaimedID), ...
                    info.Reason);
                app.setStatus('Factor 1 failed or claimed ID mismatched.',cfail);
            end
            app.updateAudit();
        end

        function onChallenge(app,digits)
            if ~isgraphics(app.UIFigure), return; end
            app.ExpectedDigits=digits;
            app.ActiveStep=3;
            app.setStepState(3,'Get ready',[0.08 0.29 0.63]);
            app.setPrompt('FACTOR 2   |   FRESH RANDOM CHALLENGE', ...
                ['SAY  ',app.digitsAsText(digits)], ...
                'Speak each digit separately with a short pause.', ...
                [0.08 0.29 0.63]);
            app.setStatus('All three digits AND claimed speaker must match.', ...
                [0.08 0.29 0.63]);
            app.updateAudit();
        end

        function onFactor2(app,passed,info)
            if ~isgraphics(app.UIFigure), return; end
            app.Factor2Info=info;
            app.Factor2Seen=true;
            if passed
                app.setStepState(3,'Passed',[0.05 0.48 0.28]);
                app.setStatus('Factor 2 passed: digits + speaker.',[0.05 0.48 0.28]);
            else
                app.setStepState(3,'Denied',[0.78 0.08 0.08]);
                app.setStatus('Factor 2 denied: see scores in Command Window.', ...
                    [0.78 0.08 0.08]);
            end
            app.updateAudit();
        end

        function onNotice(app,stage,reason)
            if ~isgraphics(app.UIFigure), return; end
            app.setStatus(sprintf('%s: %s',upper(char(stage)),reason),[0.78 0.08 0.08]);
            app.setAudit({['Claimed ID: ',app.ClaimedID],reason});
        end

        function renderFinal(app,ok,speaker,report)
            if ~isgraphics(app.UIFigure), return; end
            % In a no-speech attempt or claim rejection, the backend may
            % return before either diagnostic event. Do not fabricate scores.
            if isfield(report,'Factor1') && isstruct(report.Factor1)
                app.Factor1Info=report.Factor1;
            end
            if isfield(report,'Factor2') && isstruct(report.Factor2) && ...
                    ~isempty(report.Factor2)
                app.Factor2Seen=true;
                app.Factor2Info=report.Factor2;
            end
            if ok
                app.setDecision('ACCESS GRANTED',[0.05 0.48 0.28], ...
                    sprintf('Claimed: %s   |   Speaker: %s',app.ClaimedID,speaker), ...
                    'Factor 1 PASSED  |  Factor 2 PASSED');
                app.setStatus('Both factors passed.',[0.05 0.48 0.28]);
                app.Factor1Passed=true;
            else
                if app.Factor1Passed
                    speakerText=sprintf('Claimed: %s   |   Verified speaker: %s', ...
                        app.ClaimedID,app.fieldOr(app.Factor1Info,'BestRoll','UNKNOWN'));
                else
                    speakerText=sprintf('Claimed: %s   |   Best match (unverified): %s', ...
                        app.ClaimedID,app.fieldOr(app.Factor1Info,'BestRoll','NONE'));
                end
                app.setDecision('ACCESS DENIED',[0.78 0.08 0.08], ...
                    speakerText,report.Reason);
                app.setStatus(sprintf('Denied at %s.',report.Stage),[0.78 0.08 0.08]);
            end
            app.StepLabel.Text='VERIFICATION COMPLETE';
            app.HintLabel.Text='';
            app.PromptLabel.Text='Press START VERIFICATION for the next student';
            app.TimerLabel.Text='';
            app.updateAudit();
        end

        function updateAudit(app)
            % Compact five-line visible digest; full original reports are
            % still sent verbatim to the native MATLAB Command Window.
            claim=app.ClaimedID;
            f1=app.Factor1Info;
            f2=app.Factor2Info;
            best=app.fieldOr(f1,'BestRoll','NOT VERIFIED');
            if isempty(fieldnames(f1))
                first='PENDING';
            elseif app.Factor1Passed
                first='PASSED';
            else
                first='FAILED';
            end
            lines={sprintf('FACTOR 1: %s   |   Claimed ID: %s',first,claim), ...
                   sprintf('Best speaker match: %s',best)};
            if isfield(f1,'Sd') && isfield(f1,'Rolls') && isfield(f1,'Voice')
                ix=find(strcmp(f1.Rolls,best),1);
                if ~isempty(ix)
                    lines{end+1}=sprintf('F1 phrase %.3f / %.3f  |  LLR %.3f / %.3f  |  rank %d', ...
                        f1.Sd(ix),f1.ThetaPhrase,f1.Voice(ix),f1.VoiceGate,f1.VoiceRank);
                end
            end
            if isempty(app.ExpectedDigits)
                lines{end+1}='FACTOR 2: NOT RUN';
            elseif ~app.Factor2Seen
                lines{end+1}=sprintf('FACTOR 2: PENDING  |  Expected: %s', ...
                    app.digitsAsText(app.ExpectedDigits));
            else
                exp=app.fieldOr(f2,'Expected',app.ExpectedDigits);
                recognized=app.fieldOr(f2,'Recognized',nan(1,3));
                if app.fieldOr(f2,'ContentPass',false) && ...
                        app.fieldOr(f2,'VoicePass',false)
                    second='PASSED';
                else
                    second='DENIED';
                end
                lines{end+1}=sprintf('FACTOR 2: %s  |  Expected: %s  |  Recognized: %s', ...
                    second,app.digitsAsText(exp),app.digitsAsText(recognized));
                rank=app.fieldOr(f2,'VoiceRank',nan);
                llr=app.fieldOr(f2,'VoiceLLR',nan);
                gate=app.fieldOr(f2,'VoiceGate',nan);
                lines{end+1}=sprintf('F2 Speaker rank: %s  |  LLR: %.3f  |  Gate: %.3f', ...
                    app.fmtNumber(rank),llr,gate);
            end
            app.setAudit(lines);
        end

        function str=digitsAsText(app,digits)
            %#ok<INUSD>
            if isempty(digits), str='N/A'; return; end
            tokens=cell(1,numel(digits));
            for k=1:numel(digits)
                if isnan(digits(k)) || ~isfinite(digits(k))
                    tokens{k}='?';
                else
                    tokens{k}=sprintf('%d',digits(k));
                end
            end
            str=strjoin(tokens,'  ');
        end

        function out=fieldOr(app,s,key,fallback)
            %#ok<INUSD>
            if isstruct(s) && isscalar(s) && isfield(s,key) && ~isempty(s.(key))
                out=s.(key);
            else
                out=fallback;
            end
        end

        function str=fmtNumber(app,x)
            %#ok<INUSD>
            if isnumeric(x) && isscalar(x) && isfinite(x)
                str=sprintf('%d',x);
            else
                str='N/A';
            end
        end

        function setStatus(app, text, colour)
            app.StatusLabel.Text = text;
            app.StatusLabel.FontColor = colour;
            drawnow;
        end

        function setPrompt(app, stepText, promptText, hintText, colour)
            app.StepLabel.Text   = stepText;
            app.PromptLabel.Text = promptText;
            app.PromptLabel.FontColor = colour;
            app.HintLabel.Text   = hintText;
            drawnow;
        end

        function setStepState(app, step, text, colour)
            if nargin < 4, colour = [0.42 0.43 0.48]; end
            switch step
                case 1
                    h = app.NameStateLabel;
                case 2
                    h = app.IDStateLabel;
                case 3
                    h = app.ChallengeStateLabel;
                otherwise
                    return;
            end
            h.Text = text;
            h.FontColor = colour;
            drawnow;
        end

        function resetStepStates(app)
            c = [0.42 0.43 0.48];
            app.NameStateLabel.Text = 'Waiting';
            app.NameStateLabel.FontColor = c;
            app.IDStateLabel.Text = 'Waiting';
            app.IDStateLabel.FontColor = c;
            app.ChallengeStateLabel.Text = 'Waiting';
            app.ChallengeStateLabel.FontColor = c;
        end

        function [axW, axS, accent] = activeAxes(app)
            switch app.ActiveStep
                case 1
                    axW = app.NameWaveformAxes;
                    axS = app.NameSpectrumAxes;
                    accent = [0.05 0.48 0.28];
                case 2
                    axW = app.IDWaveformAxes;
                    axS = app.IDSpectrumAxes;
                    accent = [0.43 0.18 0.57];
                case 3
                    axW = app.ChallengeWaveformAxes;
                    axS = app.ChallengeSpectrumAxes;
                    accent = [0.08 0.29 0.63];
                otherwise
                    axW = app.NameWaveformAxes;
                    axS = app.NameSpectrumAxes;
                    accent = [0.08 0.29 0.63];
            end
        end

        function styleAxis(app, ax, titleText, xText, yText)
            ax.Color = [1 1 1];
            ax.Box = 'on';
            ax.XGrid = 'on';
            ax.YGrid = 'on';
            ax.GridColor = [0.86 0.87 0.90];
            ax.GridAlpha = 0.55;
            ax.FontName = 'Segoe UI';
            ax.FontSize = 8;
            ax.LineWidth = 0.8;
            ax.XColor = [0.42 0.43 0.48];
            ax.YColor = [0.42 0.43 0.48];
            title(ax, titleText, 'FontName','Segoe UI','FontWeight','bold', ...
                'FontSize',9,'Color',[0.14 0.14 0.16]);
            xlabel(ax, xText, 'FontName','Segoe UI','FontSize',8, ...
                'Color',[0.42 0.43 0.48]);
            ylabel(ax, yText, 'FontName','Segoe UI','FontSize',8, ...
                'Color',[0.42 0.43 0.48]);
        end

        function clearSignalAxes(app, axW, axS)
            cla(axW); cla(axS);
            xlim(axW,[0 1]); ylim(axW,[-1 1]);
            xlim(axS,[0 app.Cfg.RecordFs/2]); ylim(axS,[0 1]);
            app.styleAxis(axW,'Waveform','Time (s)','Amplitude');
            app.styleAxis(axS,'Spectrum','Frequency (Hz)','Magnitude');
        end

        function clearAllSignalAxes(app)
            app.clearSignalAxes(app.NameWaveformAxes, app.NameSpectrumAxes);
            app.clearSignalAxes(app.IDWaveformAxes, app.IDSpectrumAxes);
            app.clearSignalAxes(app.ChallengeWaveformAxes, app.ChallengeSpectrumAxes);
        end

        function showWaveform(app, x, ~)
            [axW, ~, accent] = app.activeAxes();
            if isempty(x), return; end
            x = double(x(:));
            t = (0:numel(x)-1) / app.Cfg.RecordFs;
            % Long recordings are decimated for DISPLAY ONLY.
            stride = max(1, ceil(numel(x)/12000));
            plot(axW,t(1:stride:end),x(1:stride:end),'Color',accent,'LineWidth',1.0);
            app.styleAxis(axW,'Waveform','Time (s)','Amplitude');
            xlim(axW,[0 max(0.1,t(end))]);
            ymax=max(abs(x));
            ylim(axW,1.1*[-max(0.01,ymax),max(0.01,ymax)]);
            drawnow;
        end

        function showSpectrum(app, x, ~)
            [~, axS, accent] = app.activeAxes();
            if isempty(x), return; end
            % This is the ORIGINAL microphone audio, displayed only. No
            % Group 04 filter/noise-reduction or scoring is ever invoked.
            x = double(x(:));
            stride = max(1,ceil(numel(x)/65536));
            z=x(1:stride:end);
            fsDisplay=app.Cfg.RecordFs/stride;
            nfft=2^nextpow2(max(1024,numel(z)));
            mag=abs(fft(z,nfft))/max(1,numel(z));
            half=1:(floor(nfft/2)+1);
            f=(half-1)*fsDisplay/nfft;
            plot(axS,f,mag(half),'Color',accent,'LineWidth',1.0);
            app.styleAxis(axS,'Spectrum','Frequency (Hz)','Magnitude');
            xlim(axS,[0,max(100,fsDisplay/2)]);
            valid=mag(half); valid=valid(isfinite(valid));
            if isempty(valid) || max(valid)<=0
                ylim(axS,[0 1]);
            else
                ylim(axS,[0 1.10*max(valid)]); % all peaks visible
            end
            drawnow;
        end

        function setDecision(app, headline, colour, identityText, detailText)
            if nargin < 4, identityText = ''; end
            if nargin < 5, detailText = ''; end
            app.DecisionLabel.Text = headline;
            app.DecisionLabel.FontColor = colour;
            app.IdentityLabel.Text = identityText;
            app.DetailLabel.Text = detailText;
            drawnow;
        end

        function setAudit(app, lines)
            if ischar(lines) || isstring(lines)
                lines = cellstr(lines);
            end
            if isempty(lines)
                lines = {''};
            end
            app.AuditArea.Value = lines;
            drawnow;
        end


        function pos = npos(app, parentSize, normPos)
            %#ok<INUSD> Convert original Group 04 normalized design coords.
            pos = [normPos(1)*parentSize(1), normPos(2)*parentSize(2), ...
                normPos(3)*parentSize(1), normPos(4)*parentSize(2)];
        end
    end

    methods (Access = public)
        function app = ParkingSecuritySystemApp
            createComponents(app);
            registerApp(app,app.UIFigure);
            startupFcn(app);
            if nargout==0, clear app; end
        end
        function delete(app)
            if isgraphics(app.UIFigure), delete(app.UIFigure); end
        end
    end

    methods (Access = private)
        function [axW, axS, stateLabel] = makeSignalRow(app, y, h, titleText, accent, C)
            figSize = app.BaseFigureSize;
            p = uipanel(app.UIFigure,'Position',app.npos(figSize,[0.02 y 0.96 h]), ...
                'BackgroundColor',C.panel,'BorderType','line','HighlightColor',C.border);
            ps = p.Position(3:4);

            uilabel(p,'Position',app.npos(ps,[0.015 0.825 0.62 0.145]), ...
                'Text',titleText,'HorizontalAlignment','left','FontName','Segoe UI', ...
                'FontWeight','bold','FontSize',11,'FontColor',accent);

            stateLabel = uilabel(p,'Position',app.npos(ps,[0.78 0.825 0.20 0.145]), ...
                'Text','Waiting','HorizontalAlignment','right','FontName','Segoe UI', ...
                'FontWeight','bold','FontSize',10,'FontColor',C.muted);

            % Keep the complete axes decorations inside the row panel.  UIAxes
            % labels extend below the plotting rectangle, so leave an explicit
            % bottom margin for tick labels and the x-axis label instead of
            % letting them spill outside the panel.
            % Taller axes, closer to the proportions of the earlier GUI.
            % Keep enough lower margin for Time/Frequency labels while using
            % substantially more of the available row height.
            axW = uiaxes(p,'Position',app.npos(ps,[0.045 0.125 0.425 0.665]));
            axS = uiaxes(p,'Position',app.npos(ps,[0.545 0.125 0.425 0.665]));

            app.styleAxis(axW,'Waveform','Time (s)','Amplitude');
            app.styleAxis(axS,'Spectrum','Frequency (Hz)','Magnitude');
        end

        function createComponents(app)

            % Colors and positions copied from the Group 04 GUI.

            C.bg     = [0.965 0.968 0.975];
            C.panel  = [0.995 0.995 0.990];
            C.white  = [1 1 1];
            C.navy   = [0.07 0.16 0.32];
            C.blue   = [0.08 0.29 0.63];
            C.green  = [0.05 0.48 0.28];
            C.purple = [0.43 0.18 0.57];
            C.gold   = [0.95 0.79 0.14];
            C.text   = [0.14 0.14 0.16];
            C.muted  = [0.42 0.43 0.48];
            C.border = [0.73 0.74 0.78];

            % Fixed full-size pixel layout. The window is maximized once at
            % startup and then resizing is disabled. No resize callbacks or
            % dynamic font/position scaling are used.
            app.BaseFigureSize = [1500 850];
            app.UIFigure = uifigure('Name', 'Anti-Theft System for Smart Parking Infrastructure', ...
                'Position', [35 25 app.BaseFigureSize], 'Color', C.bg, 'Resize', 'on');
            try
                app.UIFigure.WindowState = 'maximized';
                drawnow;
                fp = app.UIFigure.Position;
                if numel(fp) == 4 && fp(3) > 1000 && fp(4) > 600
                    app.BaseFigureSize = fp(3:4);
                end
            catch
                ss = get(groot,'ScreenSize');
                app.BaseFigureSize = [max(1200,ss(3)-80) max(720,ss(4)-100)];
                app.UIFigure.Position = [40 40 app.BaseFigureSize];
            end
            app.UIFigure.Resize = 'off';
            try
                app.UIFigure.AutoResizeChildren = 'off';
            catch
            end
            fs = app.BaseFigureSize;

            % ---------------- centered header ----------------
            app.TitleLabel = uilabel(app.UIFigure, ...
                'Position',app.npos(fs,[0.12 0.938 0.76 0.044]), ...
                'Text','ANTI-THEFT SYSTEM FOR SMART PARKING INFRASTRUCTURE', ...
                'HorizontalAlignment','center', 'FontName','Segoe UI', ...
                'FontWeight','bold','FontSize',22, 'FontColor',C.navy);

            app.EnrolledLabel = uilabel(app.UIFigure, ...
                'Position',app.npos(fs,[0.12 0.906 0.76 0.025]), ...
                'Text','Two-Factor Voice Authentication', ...
                'HorizontalAlignment','center','FontName','Segoe UI', ...
                'FontSize',11,'FontColor',C.muted);

            % ---------------- ID entry / Start ----------------
            ctrlPanel = uipanel(app.UIFigure, ...
                'Position',app.npos(fs,[0.02 0.790 0.315 0.105]), ...
                'BackgroundColor',C.panel,'BorderType','line','HighlightColor',C.border);
            cps = ctrlPanel.Position(3:4);

            app.ClaimIDLabel = uilabel(ctrlPanel, ...
                'Position',app.npos(cps,[0.04 0.60 0.25 0.24]), ...
                'Text','Enter Student ID','HorizontalAlignment','left', ...
                'FontName','Segoe UI','FontWeight','bold','FontSize',11, ...
                'FontColor',C.text);

            app.ClaimIDField = uieditfield(ctrlPanel,'text', ...
                'Position',app.npos(cps,[0.31 0.57 0.64 0.30]), 'Value','', ...
                'FontName','Consolas','FontSize',15,'FontColor',C.blue, ...
                'BackgroundColor',C.white,'HorizontalAlignment','center');

            app.StartButton = uibutton(ctrlPanel,'push', ...
                'Position',app.npos(cps,[0.04 0.10 0.91 0.34]), ...
                'Text','START VERIFICATION','FontName','Segoe UI', ...
                'FontWeight','bold','FontSize',13, ...
                'FontColor',C.text,'BackgroundColor',C.gold, ...
                'ButtonPushedFcn',@(btn,event) StartButtonPushed(app,event));

            % ---------------- Live status ----------------
            livePanel = uipanel(app.UIFigure, ...
                'Position',app.npos(fs,[0.35 0.780 0.63 0.115]), ...
                'BackgroundColor',C.white,'BorderType','line','HighlightColor',C.border);
            lps = livePanel.Position(3:4);

            app.LiveHeadingLabel = uilabel(livePanel, ...
                'Position',app.npos(lps,[0.30 0.80 0.40 0.16]), 'Text','LIVE STATUS', ...
                'HorizontalAlignment','center','FontName','Segoe UI', ...
                'FontWeight','bold','FontSize',12,'FontColor',C.muted);

            app.StepLabel = uilabel(livePanel, ...
                'Position',app.npos(lps,[0.03 0.61 0.56 0.17]), 'Text','', ...
                'HorizontalAlignment','left','FontName','Segoe UI', ...
                'FontWeight','bold','FontSize',12,'FontColor',C.muted);

            app.PromptLabel = uilabel(livePanel, ...
                'Position',app.npos(lps,[0.08 0.28 0.78 0.34]), ...
                'Text','Ready  |  Enter a Student ID and press START VERIFICATION', ...
                'HorizontalAlignment','center','FontName','Segoe UI', ...
                'FontWeight','bold','FontSize',21,'FontColor',C.navy);

            app.StatusLabel = uilabel(livePanel, ...
                'Position',app.npos(lps,[0.03 0.11 0.68 0.17]), 'Text','', ...
                'HorizontalAlignment','left','FontName','Segoe UI', ...
                'FontWeight','bold','FontSize',12,'FontColor',C.muted);

            % Compatibility placeholder only.  The previous helper/hint line
            % at the bottom of LIVE STATUS is intentionally not displayed.
            % setPrompt() may still assign Text to this handle, but it remains
            % hidden so the live-status panel contains only the four requested
            % elements: step, prompt, status and timer/Done controls.
            app.HintLabel = uilabel(livePanel, ...
                'Position',[1 1 1 1], 'Text','', 'Visible','off');

            app.TimerLabel = uilabel(livePanel, ...
                'Position',app.npos(lps,[0.68 0.59 0.29 0.18]), 'Text','', ...
                'HorizontalAlignment','right','FontName','Segoe UI', ...
                'FontSize',11,'FontColor',C.muted);

            app.DoneButton = uibutton(livePanel,'push', ...
                'Position',app.npos(lps,[0.78 0.04 0.19 0.30]), 'Text','Done', ...
                'FontName','Segoe UI','FontSize',14,'FontWeight','bold', ...
                'Visible','off','Enable','off','BackgroundColor',[0.20 0.55 0.30], ...
                'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(btn,event) DoneButtonPushed(app,event));

            % ---------------- three waveform/spectrum rows ----------------
            rowY = [0.595 0.402 0.209];
            rowH = 0.182;

            [app.IDWaveformAxes, app.IDSpectrumAxes, app.IDStateLabel] = ...
                app.makeSignalRow(rowY(1), rowH, ...
                'FACTOR 1  -  STUDENT ID VERIFICATION', C.purple, C);
            [app.NameWaveformAxes, app.NameSpectrumAxes, app.NameStateLabel] = ...
                app.makeSignalRow(rowY(2), rowH, ...
                'FACTOR 1  -  NAME VOICE VERIFICATION', C.green, C);
            [app.ChallengeWaveformAxes, app.ChallengeSpectrumAxes, app.ChallengeStateLabel] = ...
                app.makeSignalRow(rowY(3), rowH, ...
                'FACTOR 2  -  3-DIGIT CHALLENGE', C.blue, C);

            % ---------------- terminal decision ----------------
            decisionPanel = uipanel(app.UIFigure, ...
                'Position',app.npos(fs,[0.02 0.025 0.45 0.160]), ...
                'BackgroundColor',C.panel,'BorderType','line','HighlightColor',C.border);
            dps = decisionPanel.Position(3:4);

            uilabel(decisionPanel,'Position',app.npos(dps,[0.02 0.75 0.96 0.22]), ...
                'Text','TERMINAL DECISION','HorizontalAlignment','left', ...
                'FontName','Segoe UI','FontWeight','bold','FontSize',11,'FontColor',C.text);

            app.DecisionLabel = uilabel(decisionPanel, ...
                'Position',app.npos(dps,[0.03 0.45 0.94 0.31]), 'Text','READY', ...
                'HorizontalAlignment','center','FontName','Segoe UI', ...
                'FontWeight','bold','FontSize',28,'FontColor',C.text);

            app.IdentityLabel = uilabel(decisionPanel, ...
                'Position',app.npos(dps,[0.03 0.25 0.94 0.19]), 'Text','', ...
                'HorizontalAlignment','center','FontName','Segoe UI', ...
                'FontWeight','bold','FontSize',14,'FontColor',[0.08 0.29 0.63]);

            app.DetailLabel = uilabel(decisionPanel, ...
                'Position',app.npos(dps,[0.03 0.035 0.94 0.22]), ...
                'Text','Waiting for verification to begin.', ...
                'HorizontalAlignment','center','FontName','Segoe UI', ...
                'FontSize',11.5,'FontColor',C.muted);

            % ---------------- audit details ----------------
            auditPanel = uipanel(app.UIFigure, ...
                'Position',app.npos(fs,[0.485 0.025 0.495 0.160]), ...
                'BackgroundColor',C.panel,'BorderType','line','HighlightColor',C.border);
            aps = auditPanel.Position(3:4);

            uilabel(auditPanel,'Position',app.npos(aps,[0.02 0.75 0.96 0.22]), ...
                'Text','VERIFICATION AUDIT DETAILS','HorizontalAlignment','left', ...
                'FontName','Segoe UI','FontWeight','bold','FontSize',10,'FontColor',C.text);

            app.AuditArea = uitextarea(auditPanel, ...
                'Position',app.npos(aps,[0.02 0.10 0.96 0.60]), 'Editable','off', ...
                'FontName','Consolas','FontSize',9, ...
                'FontColor',C.text,'BackgroundColor',C.white, ...
                'Value',{'Waiting for verification to begin.'});

            % Legacy invisible Group 04 controls are intentionally omitted.
            app.ScoreLabel = uilabel(app.UIFigure, ...
                'Position',[0 0 1 1],'Text','','Visible','off');
            % Fixed-size GUI: no SizeChangedFcn or resize scaling is installed.
        end
    end
end
