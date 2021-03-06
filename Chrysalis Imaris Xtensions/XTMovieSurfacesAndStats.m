%
%  Installation:
%
%  -For this XTension to work:
%  
%   1)	Create a new Folder for �batchable� XTensions
%       a.	c:/Program Files/Bitplane/BatchXTensions
%       b.	This folder can be made anywhere, but should be in public folder
%   2)	Download XTBatchProcess.m to this folder
%   3)	Download XTChrysalis2phtn.m to this folder
%   4)  Create a new folder that will contain the processed Imaris files and exported
%       statistics that are generated by this Xtension
%       a. g:/BitplaneBatchOutput
%       b. A folder titled BitplaneBatchOutput can be made anywhere just
%       change line 249 of this script to reflect its location.
%   5)	Start Imaris and Click menu tab FIJI>>OPTIONS
%       a.	Add the BatchXTensions folder to the XTension folder window
%       b.	This is necessary for the batch process option to appear in Imaris menu
%  
%
%   NOTE: This XTension will NOT appear in the Imaris menus, and will only appear 
%   in conjunction with the running of the XTBatchProcess XTension
%   
%   NOTE:  This XTension is developed for working on Windows based machines only.
%   If you want to use it on MacOS, you will have to edit the .m file save location
%   to fit Mac standards. 
%

function XTMovieSurfacesAndStats(aImarisApplicationID)

% Parameters
offset = 0.1;

% connect to Imaris interface
if ~isa(aImarisApplicationID, 'Imaris.IApplicationPrxHelper')
  javaaddpath ImarisLib.jar
  vImarisLib = ImarisLib;
  if ischar(aImarisApplicationID)
    aImarisApplicationID = round(str2double(aImarisApplicationID));
  end
  vImarisApplication = vImarisLib.GetApplication(aImarisApplicationID);
else
  vImarisApplication = aImarisApplicationID;
end

vImarisDataSet = vImarisApplication.GetDataSet.Clone;

import java.util.Properties;
import java.io.FileReader;

% Finds out where the current m file is
baseFolder = fileparts(which(mfilename));

% Reads the property file from the same directory of the m file
propertyFilename = fullfile(baseFolder,'chrysalis.properties');
p = Properties; 
p.load(FileReader(propertyFilename)); 

% Read the property
outputPath = p.getProperty('outputPath');
convertedPath = char(outputPath);

%Convert dataset to 32bit float
vFloatType = vImarisDataSet.GetType.eTypeFloat;
vImarisDataSet.SetType(vFloatType);

%%%%%%%%%%%%%%
%% Open the corresponding .mat file with the regions
filepath = char(vImarisApplication.GetCurrentFileName);

% Find out if there is one or multiple regions
regionfilepath = [filepath(1:end-3) 'mat'];
pathstr = fileparts(regionfilepath);

try
    S = load(regionfilepath);
    todo = createSurfaces(vImarisApplication,S.clipb);
catch err
    % We are in the multiple file case
    % find out the filenames
    filesToProcess = dir([filepath(1:end-4) '_roi*.mat']);
    todo=[];
    for i = 1:length(filesToProcess)
        filepath = fullfile(pathstr,filesToProcess(i).name);
        S = load(filepath);
        todo = [todo createSurfaces(vImarisApplication,S.clipb)];
    end
end

vNonDistanceChannels = vImarisDataSet.GetSizeC;
vFileNameString = vImarisApplication.GetCurrentFileName; % returns �C:/Imaris/Images/retina.ims�
vFileName = char(vFileNameString);
scaleFactorFile = [ vFileName(1:end-4) '.scaleFactors.txt' ];
if exist(scaleFactorFile,'file')
    s = importdata(scaleFactorFile);
    scalef = s.data;
else
    scalef = [];
end

vNewFileName = doDistTransformAndSave(vImarisApplication, vImarisDataSet, todo, convertedPath);

%%%%%% Export all stats for surfaces starting with TCR
saveTable(vImarisApplication, 'TCR', vNewFileName, offset, scalef, vNonDistanceChannels);
saveTable(vImarisApplication, 'DC', vNewFileName, offset, scalef, vNonDistanceChannels);
saveTable(vImarisApplication, 'TCR', vNewFileName, 0, scalef, vNonDistanceChannels);
saveTable(vImarisApplication, 'DC', vNewFileName, 0, scalef, vNonDistanceChannels);

end

function todo = createSurfaces(vImarisApplication,clipb)

%% Figure out N
N = 0;
typs = fieldnames(clipb.regions)';

for typ = typs;
 mtyp = typ{1};

 cregs = clipb.regions.(mtyp);
 
 if ~isfield(cregs,'position')
     continue
 end
 
 N = N+numel(cregs);
end

%% Fetch measurements
%%% !! Need to modify sortomatograph to export the original objects name
%%% too (e.g. TCR Tg...) so that it can be opened here
objectsName = clipb.objectsName;

surpassObjects = xtgetsporfaces(vImarisApplication);
names = {surpassObjects.Name};
listValue = find(cellfun(@(x) strcmp(x,objectsName),names),1);
xObject = surpassObjects(listValue).ImarisObject;

statStruct = xtgetstats(vImarisApplication, xObject, 'ID', 'ReturnUnits', 1);

xData = statStruct(clipb.xvar).Values;
yData = statStruct(clipb.yvar).Values;

%% Extract surfaces for each region
xScene = vImarisApplication.GetSurpassScene;
xFactory = vImarisApplication.GetFactory;
xObject = xFactory.ToSurfaces(xObject);

todo=[];

for typ = typs;
 mtyp = typ{1};

 cregs = clipb.regions.(mtyp);
 
 if ~isfield(cregs,'position')
     continue
 end
 
 for ir = 1:length(cregs)
    regionName = cregs(ir).label;
     
    rgnVertices = toVertices(cregs(ir),mtyp);
    
    inPlotIdxs = inpolygon(xData, yData, ...
        rgnVertices(:, 1), rgnVertices(:, 2));

    % Same as create new surface with 'inside' objects
    inIDs = double(statStruct(clipb.yvar).Ids(inPlotIdxs));
    inIdxs = inIDs-double(min(statStruct(clipb.yvar).Ids));
    
    sortSurfaces = xFactory.CreateSurfaces;
    
    sortSurfaces.SetName([char(xObject.GetName) ' - ' regionName(6:end)])
    
    for s = 1:length(inIdxs)
        % Get the surface data for the current index.
        sNormals = xObject.GetNormals(inIdxs(s));
        sTime = xObject.GetTimeIndex(inIdxs(s));
        sTriangles = xObject.GetTriangles(inIdxs(s));
        sVertices = xObject.GetVertices(inIdxs(s));

        % Add the surface to the sorted Surface using the data.
        sortSurfaces.AddSurface(sVertices, sTriangles, sNormals, sTime)
    end % s

    xScene.AddChild(sortSurfaces, -1)

    todo=[todo sortSurfaces];
 end
end

end

function vNewFileName = doDistTransformAndSave(vImarisApplication, vImarisDataSet, todo, convertedPath)

vProgressDisplay = waitbar(0, 'Distance Transform: Preparation');
for vSurfaces_i=1:length(todo)
    vSurfaces = todo(vSurfaces_i)

    %vImarisApplication.DataSetPushUndo('Distance Transform');

    vDataMin = [vImarisDataSet.GetExtendMinX, vImarisDataSet.GetExtendMinY, vImarisDataSet.GetExtendMinZ];
    vDataMax = [vImarisDataSet.GetExtendMaxX, vImarisDataSet.GetExtendMaxY, vImarisDataSet.GetExtendMaxZ];
    vDataSize = [vImarisDataSet.GetSizeX, vImarisDataSet.GetSizeY, vImarisDataSet.GetSizeZ];

    %Identify if the Distance Transform will process on Spots or Surface object
    %Script chooses the first Spot or Surface object in the Surpass Scene
        vImarisObject = vImarisApplication.GetFactory.ToSurfaces(vSurfaces);
        vIsSurfaces=true;
        vSelection=2;

    % Create a new channel where the result will be sent
    vNumberOfChannels = vImarisDataSet.GetSizeC;
    vImarisDataSet.SetSizeC(vNumberOfChannels + 1);
    vImarisDataSet.SetChannelName(vNumberOfChannels,['Distance to ', char(vImarisObject.GetName)]);
    vImarisDataSet.SetChannelColorRGBA(vNumberOfChannels, 255*256*256);

    vSizeT = vImarisDataSet.GetSizeT;
    for vTime = 0:vSizeT-1;
      if vIsSurfaces

        % Get the mask DataSet
        vMaskDataSet = vImarisObject.GetMask( ...
          vDataMin(1), vDataMin(2), vDataMin(3), ...
          vDataMax(1), vDataMax(2), vDataMax(3), ...
          vDataSize(1), vDataSize(2), vDataSize(3), vTime);
        for vIndexZ = 1:vDataSize(3)
          vSlice = vMaskDataSet.GetDataSliceBytes(vIndexZ-1, 0, 0);
          if vSelection == 1
            vSlice = vSlice ~= 1;
          else
            vSlice = vSlice == 1;
          end
          if strcmp(vImarisDataSet.GetType,'eTypeUInt8')
            vImarisDataSet.SetDataSliceBytes(vSlice, ...
              vIndexZ-1, vNumberOfChannels, vTime);
          elseif strcmp(vImarisDataSet.GetType,'eTypeUInt16')
            vImarisDataSet.SetDataSliceShorts(vSlice, ...
              vIndexZ-1, vNumberOfChannels, vTime);
          elseif strcmp(vImarisDataSet.GetType,'eTypeFloat')
            vImarisDataSet.SetDataSliceFloats(vSlice, ...
              vIndexZ-1, vNumberOfChannels, vTime);
          end
        end
      end
      waitbar((vTime+1)/vSizeT/2, vProgressDisplay);
    end

    waitbar(0.5, vProgressDisplay, 'Distance Transform: Calculation');
    vImarisApplication.GetImageProcessing.DistanceTransformChannel( ...
      vImarisDataSet, vNumberOfChannels, 1, false);
    waitbar(1, vProgressDisplay);
end

vImarisApplication.SetDataSet(vImarisDataSet);

%%
% The following MATLAB code returns the name of the dataset opened in 
% Imaris and saves file as IMS (Imaris5) format
vFileNameString = vImarisApplication.GetCurrentFileName; % returns �C:/Imaris/Images/retina.ims�
vFileName = char(vFileNameString);
[vOldFolder, vName, vExt] = fileparts(vFileName); % returns [�C:/Imaris/Images/�, �retina�, �.ims�]
vNewFileName = fullfile(convertedPath, [vName, vExt]); % returns �c:/BitplaneBatchOutput/retina.ims�

%%

% Save file
vImarisApplication.FileSave(vNewFileName, '');

close(vProgressDisplay);
end

function saveTable(vImarisApplication, pattern, vNewFileName, offset, scalef, vNonDistanceChannels)

surpassObjects = xtgetsporfaces(vImarisApplication);
names = {surpassObjects.Name};
listValue = find(cellfun(@(x) ~isempty(strfind(x,pattern)),names));

for i_surf = 1:length(listValue)
    vv = listValue(i_surf);
    xObject = surpassObjects(vv).ImarisObject;

    statStruct = xtgetstats(vImarisApplication, xObject, 'ID', 'ReturnUnits', 1);
    
    statNames = {statStruct.Name};
    
    filename = [vNewFileName(1:end-4) ' - ' names{vv} ' - offset' num2str(offset) '.csv'];
    
    fd = fopen(filename,'w');
    %t = table;
    
    allstats = {'Intensity Mean','Intensity Min','Volume','Position'};
    
    headers = {};
    data = {double(statStruct(1).Ids)};
    
    for statn = 1:length(allstats)
        pat = allstats{statn};
        
        % Save Intensity Mean
        imeans = find(cellfun(@(x) ~isempty(strfind(x,pat)),statNames));

        for i = 1:length(imeans)
            imean = imeans(i);

            sname = statNames{imean};
            
            [startIndex, endIndex, tokIndex, matchStr, tokenStr, exprNames, splitStr] = regexp(sname,'Channel (?<ChNo>[0-9]+)');
            
            scalef_i = 1; 
            if ~isempty(startIndex) 
                chNo = str2double(exprNames.ChNo);
                
                chanName = char(vImarisApplication.GetDataSet.GetChannelName(chNo-1));
                
                sname = [sname(1:startIndex-1) chanName];
                
                if chNo <= vNonDistanceChannels
                    scalef_i = scalef(chNo)*.001;
                end
            end
            
            headers{end+1} = sname;
            
            data{end+1} = statStruct(imean).Values/scalef_i+offset;

            %t.(statNames{imean})=v;
        end
    end
    
    headerString = sprintf('%s,',headers{:});
    headerString = ['ID,' headerString(1:end-1)];
    
    fprintf(fd,'%s\n',headerString);
    fprintf(fd,[repmat('%f,',1,numel(data)-1) '%f\n'],cat(2,data{:})');
    
    fclose(fd);
    
    %writetable(t,filename);
end

end

function rgnVertices = toVertices(shape,typ) 
    switch typ
        case 'Ellipse'
            % Get the position of the ellipse to use for the graph.
            rgnPosition = shape.position;

            % The position vector is a bounding box. Convert the dims to radii
            % and the center.
            r1 = rgnPosition(3)/2;
            r2 = rgnPosition(4)/2;
            eCenter = [rgnPosition(1) + r1, rgnPosition(2) + r2];

            % Generate an ellipse in polar coordinates using the radii.
            theta = transpose(linspace(0, 2*pi, 100));
            r = r1*r2./(sqrt((r2*cos(theta)).^2 + (r1*sin(theta)).^2));

            [ellX, ellY] = pol2cart(theta, r);
            rgnVertices = [ellX + eCenter(1), ellY + eCenter(2)];

        case 'Poly'
            % The getPosition method returns vertices for polygons.
            rgnVertices = shape.position;

        case 'Rect'
            rgnPosition = shape.position;
            
            % Convert the x-y-width-height into the 4 corners of the rectangle.
            % The order is important to generate a rectangle, rather than a 'z'.
            rgnVertices = zeros(4, 2);
            rgnVertices(1, :) = rgnPosition(1:2); % Lower-left
            rgnVertices(2, :) = [rgnPosition(1) + rgnPosition(3), rgnPosition(2)];
            rgnVertices(3, :) = [rgnPosition(1) + rgnPosition(3), ...
                rgnPosition(2) + rgnPosition(4)];
            rgnVertices(4, :) = [rgnPosition(1), rgnPosition(2) + rgnPosition(4)];

        otherwise % It's a freehand region.
            warning('Skipping Freehand region');
    end % switch
end



