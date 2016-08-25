# RetinotopicMapping
Code to display visual stimuli and analyze data to determine the retinotopy of an LFP recording electrode. Use in conjunction with a Plexon electrophysiology system, Plexon's MATLAB Offline SDK, the Psychtoolbox, and Jeff Gavornik's StimulusSuite. The StimulusSuite is used to send event times through a DAQ to the Plexon system. Plexon outputs a .plx file.  In the MapRetinotopy.m file, I use the Offline SDK to convert a .plx to a .mat file.  This is done by the readall.m function, which I've changed locally on slightly to save the variables to a .mat file with the same name as the .plx file.
# 
The lab implants one microelectrode (3mm tip) into binocular primary visual cortex (one in each hemisphere for a total of two channels).  We then record the LFP using the Plexon system. Mice are positioned at 25 cm from a screen with a refresh rate of 80 Hz.  The specifics of your configuration can be adjusted in the RetinotopyVars.mat file, which Retinotopy.m calls for presets. The RetinotopyCallaway.m file and its supporting files, RetinotopyCallaway.frag.txt, RetinotopyCallaway.vert.txt, and MapRetinotopyCallaway.m are works in progress. We give our mice a unique identifier, e.g. 26881, corresponding to its cage ID and its personal ID within the cage.  So, we might have 26880, 26881, 26882, and 26883. 

#Steps:
1) Run Retinotopy(26881) to mouse #26881 while recording the LFP using Plexon system. Name the .plx file as RetinoDataDate_AnimalName.plx (e.g. July 5, 2016 is 20160705 so RetinoData20160705_26881.plx). Save that file to CloudStation. The Retinotopy.m file will output a file with the stimulus parameters named RetinoStim20160705_26881.mat , which will save directly to CloudStation.
#
2) Run MapRetinotopy(26881,20160705) as long as the RetinoData file and the RetinoStim file are both on the MATLAB path.
#
3) This will pop up two figures. Look at those channels and choose the best channel. The "best" channel will have the "best" retinotopy: a heat map with a clear center of greatest activity and a relatively circular decay around that center (like a 2D Gaussian). It will have large VEPs, hopefully greater than 100 microVolts. Once the figure pops up, MATLAB will also prompt you to select the best channel (use the channel name at the top of the figure, ignoring the fact that some systems start at Channel 6 or what have you). The data will be saved as RetinoMap20160705_26881.mat . This process of channel selection may be automated in the future (for example, if max VEP > 100, and 2D Gaussian fit did not return an error, then select the channel with the greatest max VEP).
#
4) In order to do subsequent analyses or stimulus generation targeting the retinotopic map, you need to choose a map. If there are multiple, it's probably best to select the most recent one. Save the final map as RetinoMap26881.mat and see Sequence-Learning repository, specifically SequenceStim.m .
#
5) If you would like to run the MapRetinotopy.m function for many animals, the best way is to use MapRetWrapper.m .  If you place all of the RetinoData and RetinoStim files into a common folder, this can easily be done by calling MapRetWrapper('RetinoData\*'). If you want to only do so for a single animal, call MapRetWrapper('RetinoData\*26881\*') . Be careful with this function, as it will take forever to run all of the data at once. It is also a work in progress.

