function [] = Retinotopy(AnimalName,holdTime)
%Retinotopy.m
%  Display a series of flashing sine-wave gratings to determine retinotopy of
%   LFP recording electrode.
%  Each circle will occupy an ~ 5-degree radius of visual space
% INPUT: Obligatory-
%        AnimalName - animal's unique identifier as a number, e.g. 45602
%
%        Optional- 
%        holdTime - time between blocks of stimuli
%  
%        see file RetinotopyVars.mat for other changeable presets
%
% OUTPUT: a file with stimulus parameters named RetinoStimDate_AnimalName
%           e.g. RetinoStim20160708_12345.mat to be saved in the RetinoExp
%           folder under '/MATLAB/Byron/'
% Created: 2016/05/24 at 24 Cummington, Boston
%  Byron Price
% Updated: 2016/08/17
%  By: Byron Price

cd('~/CloudStation/ByronExp/Retino');
load('RetinotopyVars.mat');

directory = '/home/jglab/Documents/MATLAB/Byron/Retinotopic-Mapping';
if nargin < 2
    holdTime = 30; % 30 second pauses between blocks
end
reps = reps-mod(reps,blocks);

Date = datetime('today','Format','yyyy-MM-dd');
Date = char(Date); Date = strrep(Date,'-','');Date=str2double(Date);
% Acquire a handle to OpenGL, so we can use OpenGL commands in our code:
global GL;

% Make sure this is running on OpenGL Psychtoolbox:
AssertOpenGL;

% usb = ttlInterfaceClass.getTTLInterface;
usb = usb1208FSPlusClass;
display(usb);

WaitSecs(10);

% Choose screen with maximum id - the secondary display:
screenid = max(Screen('Screens'));

% Open a fullscreen onscreen window on that display, choose a background
% color of 127 = gray with 50% max intensity; 0 = black; 255 = white
background = 127;
[win,~] = Screen('OpenWindow', screenid,background);

gammaTable = makeGrayscaleGammaTable(gama,0,255);
Screen('LoadNormalizedGammaTable',win,gammaTable);

% Switch color specification to use the 0.0 - 1.0 range
Screen('ColorRange', win, 1);

% Query window size in pixels
[w_pixels, h_pixels] = Screen('WindowSize', win);

% Retrieve monitor refresh duration
ifi = Screen('GetFlipInterval', win);

dgshader = [directory '/Retinotopy.vert.txt'];
GratingShader = LoadGLSLProgramFromFiles({ dgshader, [directory '/Retinotopy.frag.txt'] }, 1);
gratingTex = Screen('SetOpenGLTexture', win, [], 0, GL.TEXTURE_3D,w_pixels,...
    h_pixels, 1, GratingShader);

% screen size in millimeters and a conversion factor to get from mm to pixels
[w_mm,h_mm] = Screen('DisplaySize',screenid);
conv_factor = (w_mm/w_pixels+h_mm/h_pixels)/2;
mmPerPixel = conv_factor;
conv_factor = 1/conv_factor;

% perform unit conversions
Radius = (tan(degreeRadius*pi/180)*(DistToScreen*10))*conv_factor; % get number of pixels
     % that degreeRadius degrees of visual space will occupy
Radius = round(Radius);
temp = (tan((1/spatFreq)*pi/180)*(DistToScreen*10))*conv_factor;
spatFreq = 1/temp;

if strcmp(Hemisphere,'LH') == 1
    centerX = round(w_pixels/2)-100:2*Radius:w_pixels;
    centerY = Radius+1:2*Radius:h_pixels-Radius/2;
elseif strcmp(Hemisphere,'RH') == 1
    centerX = Radius+1:2*Radius:round(w_pixels/2)+100;
    centerY = Radius+1:2*Radius:h_pixels-Radius/2;
elseif strcmp(Hemisphere,'both') == 1
    centerX = 4*Radius:2*Radius:w_pixels-3*Radius;
    centerY = Radius+1:2*Radius:h_pixels-Radius/2;
end
numStimuli = length(centerX)*length(centerY);

centerVals = zeros(numStimuli,2);
count = 1;
for ii=1:length(centerX)
    for jj=1:length(centerY)
        centerVals(count,1) = centerX(ii);
        centerVals(count,2) = centerY(jj);
        count = count+1;
    end
end

for ii=1:50
    indeces = randperm(numStimuli,numStimuli);
    centerVals = centerVals(indeces,:);
end

estimatedTime = ((waitTime+stimTime)*reps*numStimuli+reps*2+blocks*holdTime)/60;
display(sprintf('\nEstimated time: %3.2f minutes',estimatedTime));


% Define first and second ring color as RGBA vector with normalized color
% component range between 0.0 and 1.0, based on Contrast between 0 and 1
% create all textures in the same window (win), each of the appropriate
% size
Grey = 0.5;
Black = 0;
White = 1;

Screen('BlendFunction',win,GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA);

orient = rand([numStimuli*reps,1]).*(2*pi);
% Perform initial flip to gray background and sync us to the retrace:
Priority(9);

usb.startRecording;WaitSecs(1);usb.strobeEventWord(0);
WaitSecs(holdTime);

% Animation loop
count = 1;
vbl = Screen('Flip',win);
for yy = 1:blocks
    for zz = 1:reps/blocks
        vbl = Screen('Flip',win,vbl+ifi/2);
        for ii=1:numStimuli
            % Draw the procedural texture as any other texture via 'DrawTexture'
            Screen('DrawTexture', win,gratingTex, [],[],...
                [],[],[],[Grey Grey Grey Grey],...
                [], [],[White,Black,...
                Radius,centerVals(ii,1),centerVals(ii,2),spatFreq,orient(count),0]);
            % Request stimulus onset
            vbl = Screen('Flip', win,vbl+ifi/2);usb.strobeEventWord(ii);
            vbl = Screen('Flip',win,vbl-ifi/2+stimTime);
            vbl = Screen('Flip',win,vbl-ifi/2+waitTime);
            count = count+1;
        end
        vbl = Screen('Flip',win,vbl-ifi/2+2);
    end
    if yy ~= blocks
        usb.strobeEventWord(0);
        vbl = Screen('Flip',win,vbl-ifi/2+holdTime);
    end
end
WaitSecs(2);
usb.stopRecording;
Priority(0);

stimParams = RetinoStimObj;
stimParams.centerVals = centerVals;
stimParams.Radius = Radius;
stimParams.reps = reps;
stimParams.stimTime = stimTime;
stimParams.holdTime = holdTime;
stimParams.numStimuli = numStimuli;
stimParams.w_pixels = w_pixels;
stimParams.h_pixels = h_pixels;
stimParams.spatFreq = spatFreq;
stimParams.mmPerPixel = mmPerPixel;
stimParams.DistToScreen = DistToScreen;
stimParams.orient = orient;


fileName = sprintf('RetinoStim%d_%d.mat',Date,AnimalName);
save(fileName,'stimParams')
% Close window
Screen('CloseAll');

end

function gammaTable = makeGrayscaleGammaTable(gamma,blackSetPoint,whiteSetPoint)
% Generates a 256x3 gamma lookup table suitable for use with the
% psychtoolbox Screen('LoadNormalizedGammaTable',win,gammaTable) command
% 
% gammaTable = makeGrayscaleGammaTable(gamma,blackSetPoint,whiteSetPoint)
%
%   gamma defines the level of gamma correction (1.8 or 2.2 common)
%   blackSetPoint should be the highest value that results in a non-unique
%   luminance value on the monitor being used (sometimes values 0,1,2, all
%   produce the same black pixel value; set to zero if this is not a
%   concern)
%   whiteSetPoint should be the lowest value that returns a non-unique
%   luminance value (deal with any saturation at the high end)
% 
%   Both black and white set points should be defined on a 0:255 scale

gamma = max([gamma 1e-4]); % handle zero gamma case
gammaVals = linspace(blackSetPoint/255,whiteSetPoint/255,256).^(1./gamma);
gammaTable = repmat(gammaVals(:),1,3);
end

