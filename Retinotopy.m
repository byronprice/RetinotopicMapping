function [] = Retinotopy(AnimalName,startHold)
%Retinotopy.m
%  Display a series of flashing gabors to determine retinotopy of
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
% Updated: 2017/07/17
%  By: Byron Price

cd('~/CloudStation/ByronExp/Retino');
load('RetinotopyVars.mat');

currentdirectory = '~/Documents/MATLAB/Byron/Retinotopic-Mapping';
cd(currentdirectory);

if nargin < 2
    startHold = 30; % 30 second pauses between blocks
end

% for motion-contingent display / interaction with recording computer
% startEXP = 254;
% endEXP = 255;
% 
% tcpipClient = tcpip('128.197.59.169',30000,'NetworkRole','client');
% bufferSize = 50000; % bytes, (we won't need this much)
% set(tcpipClient,'InputBufferSize',bufferSize);
% set(tcpipClient,'Timeout',5);
% fopen(tcpipClient);

numStimuli = numStimuli-mod(numStimuli,blocks);

reps = numStimuli/blocks;

Date = datetime('today','Format','yyyy-MM-dd');
Date = char(Date); Date = strrep(Date,'-','');Date=str2double(Date);
% Acquire a handle to OpenGL, so we can use OpenGL commands in our code:
global GL;

% Make sure this is running on OpenGL Psychtoolbox:
AssertOpenGL;

% usb = ttlInterfaceClass.getTTLInterface;
usb = usb1208FSPlusClass;
display(usb);

WaitSecs(1);

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

dgshader = [currentdirectory '/Retinotopy.vert.txt'];
GratingShader = LoadGLSLProgramFromFiles({ dgshader, [currentdirectory '/Retinotopy.frag.txt'] }, 1);
gratingTex = Screen('SetOpenGLTexture', win, [], 0, GL.TEXTURE_3D,w_pixels,...
    h_pixels, 1, GratingShader);

% screen size in millimeters and a conversion factor to get from mm to pixels
[w_mm,h_mm] = Screen('DisplaySize',screenid);
conv_factor = (w_mm/w_pixels+h_mm/h_pixels)/2;
mmPerPixel = conv_factor;
conv_factor = 1/conv_factor;

% perform unit conversions
Radius = (tan((degreeRadius/2)*pi/180)*(DistToScreen*10*2))*conv_factor; % get number of pixels
     % that degreeRadius degrees of visual space will occupy
     
temp = (tan(((1/spatFreq)/2)*pi/180)*(DistToScreen*10*2))*conv_factor;
newSpatFreq = 1/temp;

% calculate stimulus locations from a uniform distribution, but prevent
%  a stimulus from being followed by one that is close to it
DistFun = @(stimCenter,centerVals) (ceil(sqrt((stimCenter(1)-centerVals(:,1)).^2+(stimCenter(2)-centerVals(:,2)).^2))+1);

border = round(Radius);
centerVals = zeros(numStimuli,2);
centerVals(1,1) = 2*border+unidrnd(w_pixels-4*border);
centerVals(1,2) = border+unidrnd(h_pixels-2*border);

count = 2;
while count <= numStimuli
    xPos = 2*border+unidrnd(w_pixels-4*border);
    yPos = border+unidrnd(h_pixels-2*border);
    dist = DistFun(centerVals(count-1,:),[xPos,yPos]);
    if dist > 4*Radius
       centerVals(count,:) = [xPos,yPos];
       count = count+1;
    end
end

estimatedTime = ((waitTime+0.05+stimTime)*reps*blocks+blocks*holdTime)/60;
fprintf('\nEstimated time: %3.2f minutes\n',estimatedTime);

% Define first and second ring color as RGBA vector with normalized color
% component range between 0.0 and 1.0, based on Contrast between 0 and 1
% create all textures in the same window (win), each of the appropriate
% size
Grey = 0.5;
Black = 0;
White = 1;

phase = binornd(1,0.5,[numStimuli,1]);
phase = 2.*phase-1;
phase = phase.*(pi/3);

Screen('BlendFunction',win,GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA);

orientation = rand([numStimuli,1]).*(2*pi);
waitTimes = waitTime-0.05+exprnd(0.1,[numStimuli,1]);

% Perform initial flip to gray background and sync us to the retrace:
Priority(9);

usb.startRecording;WaitSecs(1);usb.strobeEventWord(0);
WaitSecs(startHold);
% usb.strobeEventWord(startEXP);WaitSecs(1);

% Animation loop
count = 1;
vbl = Screen('Flip',win);
for yy = 1:blocks
    ii=1;
    while ii<=reps
%         if tcpipClient.BytesAvailable > 0
%             data = fread(tcpipClient,tcpipClient.BytesAvailable/8,'double');
%             if sum(data) > 0
%                 WaitSecs(5);
%             else
                % Draw the procedural texture as any other texture via 'DrawTexture'
                Screen('DrawTexture',win,gratingTex, [],[],...
                    [],[],[],[Grey Grey Grey Grey],...
                    [], [],[White,Black,...
                    Radius,centerVals(count,1),centerVals(count,2),newSpatFreq,orientation(count),phase(count)]);
                % Request stimulus onset
                vbl = Screen('Flip', win);
                usb.strobeEventWord(stimStrobeNum);
                vbl = Screen('Flip',win,vbl-ifi/2+stimTime);
                vbl = Screen('Flip',win,vbl-ifi/2+waitTimes(count));
                count = count+1;
                ii=ii+1;
%             end
%         end
    end
    usb.strobeEventWord(0);
    vbl = Screen('Flip',win,vbl-ifi/2+holdTime);
end
% WaitSecs(1);usb.strobeEventWord(endEXP);
usb.stopRecording;
Priority(0);

stimParams = RetinoStimObj;
stimParams.centerVals = centerVals;
stimParams.Radius = Radius;
stimParams.degreeRadius = degreeRadius;
stimParams.stimStrobeNum = stimStrobeNum;
stimParams.stimTime = stimTime;
stimParams.holdTime = holdTime;
stimParams.waitTime = waitTime;
stimParams.numStimuli = numStimuli;
stimParams.w_pixels = w_pixels;
stimParams.h_pixels = h_pixels;
stimParams.spatFreq = spatFreq;
stimParams.mmPerPixel = mmPerPixel;
stimParams.DistToScreen = DistToScreen;
stimParams.orient = orientation;
stimParams.phase = phase;

cd('~/CloudStation/ByronExp/Retino');

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

