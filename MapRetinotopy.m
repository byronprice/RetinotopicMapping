function [stimVals,centerMass,numChans] = MapRetinotopy(AnimalName,Date,yesNo)
% MapRetinotopy.m
%
%  Will take data from a retinotopic mapping experiment and extract the
%   retinotopy of the LFP recording electrode.
%INPUT: AnimalName - unique identifier for the animal as a number, e.g.
%            12345
%       Date - date of the experiment, e.g. 20160525
%       Optional:
%        yesNo - 1 if you are running this code as is, 0 if it is being run
%         through MapRetWrapper.m or you don't want to output and save the
%         figure for whatever reason
%OUTPUT: stimVals - values used to generate the imagesc figure
%        centerMass - for each channel, a vector with x position of the
%         retinotopic field's center of mass, y position, x standard
%         deviation and y standard deviation
%        numChans - number of channels for this setup, usually 2
%
% Created: 2016/05/25, 8 St. Mary's Street, Boston
%  Byron Price
% Updated: 2016/08/18
%  By: Byron Price

cd('~/CloudStation/ByronExp/Retino');

EphysFileName = sprintf('RetinoData%d_%d',Date,AnimalName); % no file identifier
    % because MyReadall does that for us
  
global centerVals Radius reps stimTime holdTime numStimuli w_pixels h_pixels ...
    DistToScreen numChans sampleFreq stimLen minWin maxWin yesNo; %#ok<*REDEF>

StimulusFileName = sprintf('RetinoStim%d_%d.mat',Date,AnimalName);
load(StimulusFileName)

centerVals = stimParams.centerVals;
Radius = stimParams.Radius;
reps = stimParams.reps;
stimTime = stimParams.stimTime;
holdTime = stimParams.holdTime;
numStimuli = stimParams.numStimuli;
w_pixels = stimParams.w_pixels;
h_pixels = stimParams.h_pixels;
DistToScreen = stimParams.DistToScreen;

if nargin < 3
    yesNo = 1; %#ok<*NASGU>
end

% convert from allad to ChanData by filtering
[ChanData,timeStamps,tsevs,svStrobed] = ExtractSignal(EphysFileName);

% get LFP response to each stimulus (the VEPs)
[Response,meanResponse,strobeTimes] = CollectVEPS(ChanData,timeStamps,tsevs,svStrobed);

% STATISTIC OF INTEREST is T = max - min(mean(LFP across stimulus repetitions)) 
% in the interval from 0 to ~ 0.3 seconds after an image is flashed on the 
% screen, this is a measure of the size of a VEP
statFun = @(data,win) abs(min(mean(data(:,win),1)));

minWin = round(0.04*sampleFreq):1:round(0.12*sampleFreq);
maxWin = round(.1*sampleFreq):1:round(0.2*sampleFreq);
dataStats = struct;
dataStats.mean = abs(min(meanResponse(:,:,minWin),[],3)); %max(meanResponse(:,:,maxWin),[],3)-min(meanResponse(:,:,minWin),[],3);
dataStats.sem = zeros(numChans,numStimuli);
dataStats.ci = zeros(numChans,numStimuli,2);

% BOOTSTRAP FOR STANDARD ERROR OF STATISTIC IN PRESENCE OF VISUAL STIMULI
N = 2000; % number of bootstrap samples
alpha = 0.01;
for ii=1:numChans
    for jj=1:numStimuli
        Data = squeeze(Response(ii,jj,:,:));
        [~,se,ci] = Bootstraps(Data,statFun,alpha,N,reps);
        dataStats.sem(ii,jj) = se;
        dataStats.ci(ii,jj,:) = ci;
    end
end

% BOOTSTRAP FOR 95% CONFIDENCE INTERVALS OF STATISTIC IN ABSENCE OF VISUAL STIMULI
%  AND STANDARD ERRORS
%  interspersed stimulus repetitions with holdTime seconds of a blank
%  screen
noStimLen = holdTime*sampleFreq-stimLen*2;

baseStats = struct;
baseStats.ci = zeros(numChans,2);
baseStats.mean = zeros(numChans,1);
baseStats.sem = zeros(numChans,1);

for ii=1:numChans
    pauseOnset = strobeTimes(svStrobed == 0);
    nums = length(pauseOnset);
    indeces = random('Discrete Uniform',noStimLen,[reps,1]);
    temp = zeros(reps,stimLen);
    for kk=1:reps
        num = random('Discrete Uniform',nums);
        [~,index] = min(abs(timeStamps-pauseOnset(num)));
        temp(kk,:) = ChanData(index+indeces(kk):index+indeces(kk)+stimLen-1,ii);
    end
    [stat,se,ci] = Bootstraps(Data,statFun,alpha,N,reps);
    baseStats.ci(ii,:) = ci;
    baseStats.mean(ii) = stat;
    baseStats.sem(ii) = se;
end

% WALD TEST to determine which stimuli are significant
[significantStimuli] = WaldTest(dataStats,baseStats,alpha);

% Calculate the center of mass of the receptive field
[centerMass] = GetReceptiveField(significantStimuli,AnimalName);

[stimVals,h] = MakePlots(significantStimuli,meanResponse,centerMass,AnimalName); 

if yesNo == 1
    Channel = input('Type the channel that looks best (as a number, e.g. 1): ');
    savefig(h,sprintf('RetinoMap%d_%d.fig',Date,AnimalName));
    %print(h,'-depsc','filename');
end

MapParams = RetinoMapObj;
MapParams.numChans = numChans;
MapParams.centerVals = centerVals;
MapParams.significantStimuli = significantStimuli;
MapParams.centerMass = centerMass;
MapParams.stimVals = stimVals;
MapParams.Response = Response;
MapParams.meanResponse = meanResponse;
MapParams.Channel = Channel;
MapParams.dataStats = dataStats;
MapParams.baseStats = baseStats;

save(sprintf('RetinoMap%d_%d.mat',Date,AnimalName),'MapParams');

set(0,'DefaultFigureWindowStyle','normal');
% obj = gmdistribution(centerMass(Channel,1:2),squeeze(Sigma(Channel,:,:)));
% figure();
% h = ezcontour(@(x,y) pdf(obj,[x y]),[0 w_pixels,0 h_pixels]);
end

function [ChanData,timeStamps,tsevs,svStrobed] = ExtractSignal(EphysFileName)
    % Extract LFP signals from allad, filter, get timestamps
    global numChans sampleFreq;
    % read in the .plx file

    if exist(strcat(EphysFileName,'.mat'),'file') ~= 2
        MyReadall(EphysFileName);
    end

    EphysFileName = strcat(EphysFileName,'.mat');
    load(EphysFileName)

    
    sampleFreq = adfreq;

    Chans = find(~cellfun(@isempty,allad));
    numChans = length(Chans);

    % lowpass filter the data
    dataLength = length(allad{1,Chans(1)});

    ChanData = zeros(dataLength,numChans);
    preAmpGain = 1;
    for ii=1:numChans
        voltage = 1000.*((allad{1,Chans(ii)}).*SlowPeakV)./(0.5*(2^SlowADResBits)*adgains(Chans(ii))*preAmpGain);
        n = 30;
        lowpass = 100/(sampleFreq/2); % fraction of Nyquist frequency
        blo = fir1(n,lowpass,'low',hamming(n+1));
        ChanData(:,ii) = filter(blo,1,voltage);
    end

    timeStamps = 0:1/sampleFreq:dataLength/sampleFreq-1/sampleFreq;

    if length(timeStamps) ~= dataLength
        display('Error: Review allad cell array and timing')
        return;
    end
    
end

function [Response,meanResponse,strobeTimes] = CollectVEPS(ChanData,timeStamps,tsevs,svStrobed)
    global numChans numStimuli reps stimLen stimTime sampleFreq;
    strobeStart = 33;
    strobeTimes = tsevs{1,strobeStart};
    stimLen = round((stimTime+0.2)*sampleFreq); % about 250 milliseconds
    smoothKernel = 4;
    % COLLECT DATA IN THE PRESENCE OF VISUAL STIMULI
    Response = zeros(numChans,numStimuli,reps,stimLen);
    meanResponse = zeros(numChans,numStimuli,stimLen);
    for ii=1:numChans
        for jj=1:numStimuli
            stimStrobes = strobeTimes(svStrobed == jj);
            for kk=1:reps
                stimOnset = stimStrobes(kk);
                [~,index] = min(abs(timeStamps-stimOnset));
                temp = ChanData(index:index+stimLen-1,ii);
                Response(ii,jj,kk,:) = temp;
            end
            meanResponse(ii,jj,:) = smooth(mean(squeeze(Response(ii,jj,:,:)),1),smoothKernel);
        end
    end

end

function [stat,se,ci] = Bootstraps(Data,myFun,alpha,N,n)
%Bootstraps.m
%   Bootstrap estimate of the standard error of a parameter or statistic, 
%    such as the sample mean or median.
%
%INPUT: Data - the data (the random variables recorded during an
%          experiment) ... the function handle must be able to
%          appropriately handle the size and type of Data
%       myFun - function handle, e.g. myFun = @(x) mean(x)  if you want to
%        bootstrap the sample mean, so Data would need to be appropriately
%        sized, e.g. 100-by-1 for this function
%       OPTIONAL:
%       alpha - for 1-alpha confidence interval, e.g. 0.01, defaults to
%        0.05
%       N - the number of bootstrap iterations
%       n - subpopulation size (defaults to the length of the data)
%OUTPUT: stat - value of the statistic or parameter from the actual data
%        se - standard error, i.e. sqrt(variance(bootstrap estimates))
%        ci - (1-alpha)*100% confidence interval, e.g. [1,5], calculated as
%         a quantile confidence interval
%
%Created: 2016/07/11
%  Byron Price
%Updated: 2016/08/18
% By: Byron Price
global minWin;

if nargin < 3
    alpha = 0.05;
    N = 5000;
    n = length(Data);
elseif nargin < 4
    N = 5000;
    n = length(Data);
elseif nargin < 5
    n = length(Data);
end

Tboot = zeros(N,1);
ci = zeros(2,1);
for ii=1:N
    indeces = random('Discrete Uniform',n,[n,1]);
    temp = Data(indeces,:);
    Tboot(ii) = myFun(temp,minWin);
end
stat = mean(Tboot);
se = std(Tboot);
ci(1) = quantile(Tboot,alpha/2);
ci(2) = quantile(Tboot,1-alpha/2);
end

function [significantStimuli] = WaldTest(dataStats,baseStats,alpha)
        % WALD TEST - VEP magnitude significantly greater in presence of a stimulus
    %  than in the absence of a stimulus
    global numChans numStimuli;
    significantStimuli = zeros(numChans,numStimuli);
    c = norminv(1-alpha,0,1);
    for ii=1:numChans
        for jj=1:numStimuli
            W = (dataStats.mean(ii,jj)-baseStats.mean(ii))/...
                sqrt(dataStats.sem(ii,jj)^2+baseStats.sem(ii)^2);
            if W > c
                significantStimuli(ii,jj) = dataStats.mean(ii,jj); 
            end
        end    
    end
end

function [centerMass] = GetReceptiveField(significantStimuli,AnimalName)
    global numChans centerVals numStimuli;
    centerMass = struct('x',zeros(numChans,1),'y',zeros(numChans,1),...
        'Sigma',zeros(numChans,2,2));
    for ii=1:numChans
        dataX = [];dataY = [];
        for jj=1:numStimuli
            dataX = [dataX;repmat(centerVals(jj,1),[round(significantStimuli(ii,jj)),1])];
            dataY = [dataY;repmat(centerVals(jj,2),[round(significantStimuli(ii,jj)),1])];
            % this step is fairly odd. To fit the 2D Gaussian in units of pixels,
            % rather than in units of VEP magnitude, I make a distribution in
            % each dimension by creating a vector of pixel values. If the VEP
            % magnitude at the location (1200,300), (x,y), was 250 microVolts,
            % then the dataX vector will have 250 repetitions of the value 1200
            % and the dataY vector will have 250 repetitions of the value 300.
            % So, the distribution ends up being weighted more heavily by pixel
            % values with strong VEPs. The values obtained by this method for
            % the center of the retinotopic map are identical to those obtained
            % by performing a center of mass calculation (center of mass
            % exactly like those done in physics, SUM x*m / SUM m , except that
            % m is the VEP magnitude instead of the mass).
        end
        data = [dataX,dataY];

        try
            mnPDF = fitgmdist(data,1);
            centerMass.x(ii) = mnPDF.mu(1);
            centerMass.y(ii) = mnPDF.mu(2);
            centerMass.Sigma(ii,:,:) = mnPDF.Sigma;
        catch
            display(sprintf('\nError, Animal %d , Channel %d.\n',AnimalName,ii));
            centerMass.x(ii) = NaN;
            centerMass.y(ii) = NaN;
            centerMass.Sigma(ii,:,:) = NaN;
        end

    end
end

function [stimVals,h] = MakePlots(significantStimuli,meanResponse,centerMass,AnimalName)
    global numChans numStimuli w_pixels h_pixels centerVals Radius stimLen ...
        yesNo;
    sigma = Radius;
    halfwidth = 3*sigma;
    [xx,yy] = meshgrid(-halfwidth:halfwidth,-halfwidth:halfwidth);
    gaussian = exp(-(xx.*xx+yy.*yy)./(2*sigma^2));
    stimVals = zeros(numChans,w_pixels,h_pixels);
    x=1:w_pixels;
    y=1:h_pixels;

    xconv = stimLen/max(diff(sort(centerVals(:,1)))); % the max(diff(sort ...
                     % is equal to the width of the mapping stimulus (the width
                     % of the square that encloses the sinusoidal grating with
                     % overlain 2D Gaussian kernel) ... this value is
                     % equivalent to 2*Radius, which is output in the
                     % RetinoStim file, so I could use that. The only issue is
                     % that doing so would potentially preclude other types of
                     % stimuli from being analyzed by this code. As is, the
                     % code is fairly general to accept different types of
                     % mapping stimuli
    yconv = 1000/max(diff(sort(centerVals(:,2)))); % for height of the stimulus

    if yesNo == 1
        for ii=1:numChans
            h(ii) = figure;
        end
    end
    for ii=1:numChans
        if yesNo == 1 
            figure(h(ii));axis([0 w_pixels 0 h_pixels]);
            title(sprintf('VEP Retinotopy, Channel %d, Animal %d',ii,AnimalName));
            xlabel('Horizontal Screen Position (pixels)');ylabel('Vertical Screen Position (pixels)');
            hold on;
        end
        for jj=1:numStimuli
            tempx = centerVals(jj,1);
            tempy = centerVals(jj,2);
            stimVals(ii,tempx-Radius:tempx+Radius,tempy-Radius:tempy+Radius) = significantStimuli(ii,jj);
            if yesNo == 1
                plot(((1:1:stimLen)./xconv+centerVals(jj,1)-0.5*max(diff(sort(centerVals(:,1))))),...
                    (squeeze(meanResponse(ii,jj,:))'./yconv+centerVals(jj,2)),'k','LineWidth',2);
                plot((tempx-Radius)*ones(Radius*2+1,1),(tempy-Radius):(tempy+Radius),'k','LineWidth',2);
                plot((tempx+Radius)*ones(Radius*2+1,1),(tempy-Radius):(tempy+Radius),'k','LineWidth',2);
                plot((tempx-Radius):(tempx+Radius),(tempy-Radius)*ones(Radius*2+1,1),'k','LineWidth',2);
                plot((tempx-Radius):(tempx+Radius),(tempy+Radius)*ones(Radius*2+1,1),'k','LineWidth',2);
            end
        end
        if isnan(centerMass.x(ii)) ~= 1
    %         obj = gmdistribution(centerMass(ii,1:2),squeeze(Sigma(ii,:,:)));
    %         combos = zeros(w_pixels*h_pixels,2);
    %         count = 1;
    %         for kk=1:w_pixels
    %             for ll=h_pixels:-1:1
    %                 %             stimVals(ii,kk,ll) = pdfFun(kk,ll);
    %                 combos(count,:) = [kk,ll];
    %                 count = count+1;
    %             end
    %         end
    %         temp = reshape(pdf(obj,combos),[h_pixels,w_pixels]);
    %         temp = flipud(temp)';
    %         stimVals(ii,:,:) = (temp./(max(max(temp)))).*max(significantStimuli(ii,:));
            temp = squeeze(stimVals(ii,:,:))';
            blurred = conv2(temp,gaussian,'same');
            blurred = (blurred./max(max(blurred))).*max(max(temp));
            if yesNo == 1
                imagesc(x,y,blurred,'AlphaData',0.5);set(gca,'YDir','normal');w=colorbar;
                ylabel(w,'VEP Negativity (\muV)');colormap('jet');
                hold off;
            end
        end
    end
end
