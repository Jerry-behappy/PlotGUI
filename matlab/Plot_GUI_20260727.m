function Plot_GUI_20260727
%CODE 交互式光谱数据绘图工具。
% 运行 code 后，可选择数据文件、坐标列、坐标范围及线性/对数尺度。

%% 初始化路径、用户偏好和运行状态
% 图形属性、窗口大小和自定义图例均保存在 MATLAB 用户偏好中。
app.dataFolder = fileparts(mfilename('fullpath'));
app.defaultCalibrationName = 'PC+polarizer.txt';
app.preferenceGroup = 'PlotGUI';
app.styleSettings = loadStyleSettings(app.preferenceGroup);
app.legendLabels = loadLegendLabels(app.preferenceGroup);
app.windowPosition = loadWindowPosition(app.preferenceGroup);
app.axisSettings = loadAxisSettings(app.preferenceGroup);
app.dataColumnSettings = loadDataColumnSettings(app.preferenceGroup);
app.dataScaleSettings = loadDataScaleSettings(app.preferenceGroup);
app.yCompensationValue = loadYCompensation(app.preferenceGroup);
app.smoothPointsValue = loadSmoothPoints(app.preferenceGroup);
app.appliedYCompensation = app.yCompensationValue;
app.selectedFiles = {};
app.selectionUpdateTimer = [];
app.currentCurveHandles = gobjects(0);
app.currentCurveLabels = {};
app.yLimitLineHandles = gobjects(0);

%% 创建主窗口
% uigridlayout 负责响应窗口缩放，因此关闭 Figure 自带的子控件缩放。
app.fig = uifigure( ...
    'Name', '数据绘图GUI', ...
    'Color', [0.97 0.97 0.97], ...
    'AutoResizeChildren', 'off', ...
    'Position', app.windowPosition);
app.fig.SizeChangedFcn = @persistWindowPosition;
app.fig.CloseRequestFcn = @closeApp;

%% 顶部署名与四列主布局
rootGrid = uigridlayout(app.fig, [2 1]);
rootGrid.RowHeight = {32, '1x'};
rootGrid.ColumnWidth = {'1x'};
rootGrid.Padding = [10 6 10 10];
rootGrid.RowSpacing = 6;

signatureLabel = createLabel(rootGrid, ...
    'Text', 'By Junyi Zhang, JNU MWP | 最新修改：2026-07-27', ...
    'HorizontalAlignment', 'right', ...
    'FontSize', 16, ...
    'FontWeight', 'bold', ...
    'FontColor', [0.30 0.34 0.38]);
signatureLabel.Layout.Row = 1;

mainGrid = uigridlayout(rootGrid, [1 4]);
mainGrid.Layout.Row = 2;
mainGrid.ColumnWidth = {300, 230, 300, '1x'};
mainGrid.Padding = [0 0 0 0];
mainGrid.ColumnSpacing = 8;

% 左列：目录、文件多选列表和绘图命令。
filePanel = uipanel(mainGrid, 'Title', '文件与绘图', 'FontWeight', 'bold');
fileGrid = uigridlayout(filePanel, [8 4]);
fileGrid.RowHeight = {22, 30, 22, '1x', 30, 22, 30, 36};
fileGrid.ColumnWidth = {'1x', '1x', '1x', '1x'};
fileGrid.Padding = [10 10 10 10];
fileGrid.RowSpacing = 6;

% 中间两列：坐标设置与数据处理。
controlPanel = uipanel(mainGrid, 'Title', '坐标设置', 'FontWeight', 'bold');
processPanel = uipanel(mainGrid, 'Title', '数据处理', 'FontWeight', 'bold');
rightGrid = uigridlayout(mainGrid, [2 1]);
rightGrid.RowHeight = {292, '1x'};
rightGrid.Padding = [0 0 0 0];
rightGrid.RowSpacing = 8;

controlGrid = uigridlayout(controlPanel, [11 2]);
controlGrid.RowHeight = {22, 30, 30, 30, 30, 22, 30, 30, 30, 30, '1x'};
controlGrid.ColumnWidth = {72, '1x'};
controlGrid.Padding = [10 10 10 10];
controlGrid.RowSpacing = 6;
controlGrid.ColumnSpacing = 6;

processGrid = uigridlayout(processPanel, [15 4]);
processGrid.RowHeight = {22, 30, 30, 30, 30, 30, 22, 30, 22, 30, 30, 36, 30, 30, 36};
processGrid.ColumnWidth = {60, '1x', 60, '1x'};
processGrid.Padding = [10 10 10 10];
processGrid.RowSpacing = 6;

folderLabel = createLabel(fileGrid, 'Text', '数据目录');
folderLabel.Layout.Row = 1;
folderLabel.Layout.Column = [1 4];

app.folderField = uieditfield(fileGrid, 'text', ...
    'Value', app.dataFolder, 'Editable', 'off');
app.folderField.Layout.Row = 2;
app.folderField.Layout.Column = [1 3];

browseButton = uibutton(fileGrid, 'Text', '选择...', ...
    'ButtonPushedFcn', @chooseFolder);
browseButton.Layout.Row = 2;
browseButton.Layout.Column = 4;

fileLabel = createLabel(fileGrid, 'Text', '作图文件（可多选）');
fileLabel.Layout.Row = 3;
fileLabel.Layout.Column = [1 4];

app.fileList = uilistbox(fileGrid, ...
    'Multiselect', 'on', ...
    'ClickedFcn', @toggleFileSelection, ...
    'DoubleClickedFcn', @previewSelectedFile);
app.fileList.Layout.Row = 4;
app.fileList.Layout.Column = [1 4];

selectAllButton = uibutton(fileGrid, 'Text', '全选', ...
    'ButtonPushedFcn', @selectAllFiles);
selectAllButton.Layout.Row = 5;
selectAllButton.Layout.Column = 1;

clearButton = uibutton(fileGrid, 'Text', '清空', ...
    'ButtonPushedFcn', @clearSelection);
clearButton.Layout.Row = 5;
clearButton.Layout.Column = 2;

refreshButton = uibutton(fileGrid, 'Text', '刷新', ...
    'ButtonPushedFcn', @refreshFiles);
refreshButton.Layout.Row = 5;
refreshButton.Layout.Column = [3 4];

columnLabel = createLabel(fileGrid, 'Text', '数据列');
columnLabel.Layout.Row = 6;
columnLabel.Layout.Column = [1 4];

xColumnLabel = createLabel(fileGrid, 'Text', 'X 列');
xColumnLabel.Layout.Row = 7;
xColumnLabel.Layout.Column = 1;
app.xColumn = uispinner(fileGrid, 'Limits', [1 Inf], ...
    'RoundFractionalValues', 'on', ...
    'Value', app.dataColumnSettings.xColumn, ...
    'ValueChangedFcn', @dataColumnChanged);
app.xColumn.Layout.Row = 7;
app.xColumn.Layout.Column = 2;

yColumnLabel = createLabel(fileGrid, 'Text', 'Y 列');
yColumnLabel.Layout.Row = 7;
yColumnLabel.Layout.Column = 3;
app.yColumn = uispinner(fileGrid, 'Limits', [1 Inf], ...
    'RoundFractionalValues', 'on', ...
    'Value', app.dataColumnSettings.yColumn, ...
    'ValueChangedFcn', @dataColumnChanged);
app.yColumn.Layout.Row = 7;
app.yColumn.Layout.Column = 4;

rangeLabel = createLabel(controlGrid, 'Text', '坐标范围（留空表示自动）');
rangeLabel.Layout.Row = 1;
rangeLabel.Layout.Column = [1 2];

xMinimumLabel = createLabel(controlGrid, 'Text', 'X 最小');
xMinimumLabel.Layout.Row = 2;
xMinimumLabel.Layout.Column = 1;
app.xMin = uieditfield(controlGrid, 'numeric', 'AllowEmpty', 'on', ...
    'Value', app.axisSettings.xMin, ...
    'ValueChangedFcn', @manualAxisLimitChanged);
app.xMin.Layout.Row = 2;
app.xMin.Layout.Column = 2;

xMaximumLabel = createLabel(controlGrid, 'Text', 'X 最大');
xMaximumLabel.Layout.Row = 3;
xMaximumLabel.Layout.Column = 1;
app.xMax = uieditfield(controlGrid, 'numeric', 'AllowEmpty', 'on', ...
    'Value', app.axisSettings.xMax, ...
    'ValueChangedFcn', @manualAxisLimitChanged);
app.xMax.Layout.Row = 3;
app.xMax.Layout.Column = 2;

yMinimumLabel = createLabel(controlGrid, 'Text', 'Y 最小');
yMinimumLabel.Layout.Row = 4;
yMinimumLabel.Layout.Column = 1;
app.yMin = uieditfield(controlGrid, 'numeric', 'AllowEmpty', 'on', ...
    'Value', app.axisSettings.yMin, ...
    'ValueChangedFcn', @manualAxisLimitChanged);
app.yMin.Layout.Row = 4;
app.yMin.Layout.Column = 2;

yMaximumLabel = createLabel(controlGrid, 'Text', 'Y 最大');
yMaximumLabel.Layout.Row = 5;
yMaximumLabel.Layout.Column = 1;
app.yMax = uieditfield(controlGrid, 'numeric', 'AllowEmpty', 'on', ...
    'Value', app.axisSettings.yMax, ...
    'ValueChangedFcn', @manualAxisLimitChanged);
app.yMax.Layout.Row = 5;
app.yMax.Layout.Column = 2;

scaleLabel = createLabel(controlGrid, 'Text', '坐标尺度');
scaleLabel.Layout.Row = 6;
scaleLabel.Layout.Column = [1 2];

xScaleLabel = createLabel(controlGrid, 'Text', 'X 轴');
xScaleLabel.Layout.Row = 7;
xScaleLabel.Layout.Column = 1;
app.xScale = uidropdown(controlGrid, ...
    'Items', {'linear', 'log'}, ...
    'Value', app.axisSettings.xScale, ...
    'ValueChangedFcn', @applyAxisSettings);
app.xScale.Layout.Row = 7;
app.xScale.Layout.Column = 2;

yScaleLabel = createLabel(controlGrid, 'Text', 'Y 轴');
yScaleLabel.Layout.Row = 8;
yScaleLabel.Layout.Column = 1;
app.yScale = uidropdown(controlGrid, ...
    'Items', {'linear', 'log'}, ...
    'Value', app.axisSettings.yScale, ...
    'ValueChangedFcn', @applyAxisSettings);
app.yScale.Layout.Row = 8;
app.yScale.Layout.Column = 2;

calibrationLabel = createLabel(processGrid, 'Text', '校准曲线');
calibrationLabel.Layout.Row = 1;
calibrationLabel.Layout.Column = [1 4];

app.calibrationFile = uidropdown(processGrid, ...
    'ValueChangedFcn', @replotCurrentFiles);
app.calibrationFile.Layout.Row = 2;
app.calibrationFile.Layout.Column = [1 4];

calibrationXLabel = createLabel(processGrid, 'Text', '校准 X 列');
calibrationXLabel.Layout.Row = 3;
calibrationXLabel.Layout.Column = 1;
app.calibrationXColumn = uispinner(processGrid, 'Limits', [1 Inf], ...
    'RoundFractionalValues', 'on', ...
    'Value', app.dataColumnSettings.calibrationXColumn, ...
    'ValueChangedFcn', @dataColumnChanged);
app.calibrationXColumn.Layout.Row = 3;
app.calibrationXColumn.Layout.Column = 2;

calibrationYLabel = createLabel(processGrid, 'Text', '校准 Y 列');
calibrationYLabel.Layout.Row = 3;
calibrationYLabel.Layout.Column = 3;
app.calibrationYColumn = uispinner(processGrid, 'Limits', [1 Inf], ...
    'RoundFractionalValues', 'on', ...
    'Value', app.dataColumnSettings.calibrationYColumn, ...
    'ValueChangedFcn', @dataColumnChanged);
app.calibrationYColumn.Layout.Row = 3;
app.calibrationYColumn.Layout.Column = 4;

compensationLabel = createLabel(processGrid, 'Text', 'Y 轴补偿 (dB)');
compensationLabel.Layout.Row = 5;
compensationLabel.Layout.Column = [1 2];
app.yCompensation = uieditfield(processGrid, 'numeric', ...
    'Value', app.yCompensationValue, ...
    'ValueChangedFcn', @yCompensationChanged);
app.yCompensation.Layout.Row = 5;
app.yCompensation.Layout.Column = [3 4];

xDataScaleLabel = createLabel(processGrid, 'Text', 'X 缩放');
xDataScaleLabel.Layout.Row = 6;
xDataScaleLabel.Layout.Column = 1;
app.xDataScale = uieditfield(processGrid, 'numeric', ...
    'Value', app.dataScaleSettings.xFactor, ...
    'ValueChangedFcn', @dataScaleChanged);
app.xDataScale.Layout.Row = 6;
app.xDataScale.Layout.Column = 2;

yDataScaleLabel = createLabel(processGrid, 'Text', 'Y 缩放');
yDataScaleLabel.Layout.Row = 6;
yDataScaleLabel.Layout.Column = 3;
app.yDataScale = uieditfield(processGrid, 'numeric', ...
    'Value', app.dataScaleSettings.yFactor, ...
    'ValueChangedFcn', @dataScaleChanged);
app.yDataScale.Layout.Row = 6;
app.yDataScale.Layout.Column = 4;

app.subtractCalibration = uicheckbox(processGrid, ...
    'Text', '扣除所选校准曲线', ...
    'Value', false, ...
    'ValueChangedFcn', @setCalibrationEnabled);
app.subtractCalibration.Layout.Row = 4;
app.subtractCalibration.Layout.Column = [1 4];

smoothLabel = createLabel(processGrid, 'Text', '平滑处理');
smoothLabel.Layout.Row = 7;
smoothLabel.Layout.Column = [1 4];

app.enableSmooth = uicheckbox(processGrid, ...
    'Text', '启用 smooth', ...
    'Value', false, ...
    'ValueChangedFcn', @setSmoothEnabled);
app.enableSmooth.Layout.Row = 8;
app.enableSmooth.Layout.Column = [1 2];

smoothPointsLabel = createLabel(processGrid, 'Text', '点数');
smoothPointsLabel.Layout.Row = 8;
smoothPointsLabel.Layout.Column = 3;
app.smoothPoints = uispinner(processGrid, ...
    'Limits', [1 Inf], ...
    'RoundFractionalValues', 'on', ...
    'Value', app.smoothPointsValue, ...
    'Enable', 'off', ...
    'ValueChangedFcn', @smoothPointsChanged);
app.smoothPoints.Layout.Row = 8;
app.smoothPoints.Layout.Column = 4;

curveSubtractLabel = createLabel(processGrid, 'Text', '当前曲线相减（A - B）');
curveSubtractLabel.Layout.Row = 9;
curveSubtractLabel.Layout.Column = [1 4];

curveALabel = createLabel(processGrid, 'Text', '曲线 A');
curveALabel.Layout.Row = 10;
curveALabel.Layout.Column = 1;
app.subtractCurveA = uidropdown(processGrid, ...
    'Items', {'(暂无曲线)'}, ...
    'Enable', 'off');
app.subtractCurveA.Layout.Row = 10;
app.subtractCurveA.Layout.Column = [2 4];

curveBLabel = createLabel(processGrid, 'Text', '曲线 B');
curveBLabel.Layout.Row = 11;
curveBLabel.Layout.Column = 1;
app.subtractCurveB = uidropdown(processGrid, ...
    'Items', {'(暂无曲线)'}, ...
    'Enable', 'off');
app.subtractCurveB.Layout.Row = 11;
app.subtractCurveB.Layout.Column = [2 4];

refreshCurveButton = uibutton(processGrid, ...
    'Text', '刷新曲线', ...
    'ButtonPushedFcn', @refreshCurveChoices);
refreshCurveButton.Layout.Row = 12;
refreshCurveButton.Layout.Column = [1 2];

app.curveSubtractButton = uibutton(processGrid, ...
    'Text', '相减并作图', ...
    'FontWeight', 'bold', ...
    'Enable', 'off', ...
    'ButtonPushedFcn', @plotCurveDifference);
app.curveSubtractButton.Layout.Row = 12;
app.curveSubtractButton.Layout.Column = [3 4];

saveCurveLabel = createLabel(processGrid, 'Text', '保存曲线');
saveCurveLabel.Layout.Row = 13;
saveCurveLabel.Layout.Column = 1;
app.saveCurve = uidropdown(processGrid, ...
    'Items', {'(暂无曲线)'}, ...
    'Enable', 'off');
app.saveCurve.Layout.Row = 13;
app.saveCurve.Layout.Column = [2 4];

processedFileNameLabel = createLabel(processGrid, 'Text', '文件名');
processedFileNameLabel.Layout.Row = 14;
processedFileNameLabel.Layout.Column = 1;
app.processedFileName = uieditfield(processGrid, 'text', ...
    'Value', '', ...
    'Placeholder', '留空使用曲线名');
app.processedFileName.Layout.Row = 14;
app.processedFileName.Layout.Column = [2 4];

app.saveProcessedButton = uibutton(processGrid, ...
    'Text', '保存处理后曲线数据（CSV）', ...
    'Enable', 'off', ...
    'ButtonPushedFcn', @saveCurrentProcessedCurves);
app.saveProcessedButton.Layout.Row = 15;
app.saveProcessedButton.Layout.Column = [1 4];

app.autoScaleOnPlot = uicheckbox(controlGrid, ...
    'Text', '绘图时自动缩放 X/Y 坐标范围', ...
    'Value', app.axisSettings.autoScaleOnPlot, ...
    'ValueChangedFcn', @autoScaleChanged);
app.autoScaleOnPlot.Layout.Row = 9;
app.autoScaleOnPlot.Layout.Column = [1 2];

autoButton = uibutton(controlGrid, 'Text', '自动坐标范围', ...
    'ButtonPushedFcn', @clearAxisLimits);
autoButton.Layout.Row = 10;
autoButton.Layout.Column = [1 2];

plotButton = uibutton(fileGrid, 'push', ...
    'Text', '绘图', ...
    'FontWeight', 'bold', ...
    'BackgroundColor', [0.16 0.45 0.72], ...
    'FontColor', [1 1 1], ...
    'ButtonPushedFcn', @plotSelectedFiles);
plotButton.Layout.Row = 8;
plotButton.Layout.Column = [1 4];

app.status = createLabel(controlGrid, 'Text', '请选择文件后绘图', ...
    'FontColor', [0.3 0.3 0.3], 'WordWrap', 'on');
app.status.Layout.Row = 11;
app.status.Layout.Column = [1 2];

%% 右列上部：实时图形属性
% 所有控件修改后立即调用 applyPlotStyle，并同步写入用户偏好。
stylePanel = uipanel(rightGrid, 'Title', '图形属性', 'FontWeight', 'bold');
styleGrid = uigridlayout(stylePanel, [8 4]);
styleGrid.RowHeight = {27, 27, 27, 27, 27, 27, 27, 27};
styleGrid.ColumnWidth = {80, '1x', 80, '1x'};
styleGrid.Padding = [8 6 8 6];
styleGrid.RowSpacing = 4;
styleGrid.ColumnSpacing = 6;

plotTitleLabel = createLabel(styleGrid, 'Text', '图标题');
plotTitleLabel.Layout.Row = 1;
plotTitleLabel.Layout.Column = 1;
app.titleText = uieditfield(styleGrid, 'text', ...
    'Value', app.styleSettings.titleText, ...
    'ValueChangedFcn', @applyPlotStyle);
app.titleText.Layout.Row = 1;
app.titleText.Layout.Column = [2 4];

xLabelTextLabel = createLabel(styleGrid, 'Text', 'X 轴标题');
xLabelTextLabel.Layout.Row = 2;
xLabelTextLabel.Layout.Column = 1;
app.xLabelText = uieditfield(styleGrid, 'text', ...
    'Value', app.styleSettings.xLabelText, ...
    'ValueChangedFcn', @applyPlotStyle);
app.xLabelText.Layout.Row = 2;
app.xLabelText.Layout.Column = 2;

yLabelTextLabel = createLabel(styleGrid, 'Text', 'Y 轴标题');
yLabelTextLabel.Layout.Row = 2;
yLabelTextLabel.Layout.Column = 3;
app.yLabelText = uieditfield(styleGrid, 'text', ...
    'Value', app.styleSettings.yLabelText, ...
    'ValueChangedFcn', @applyPlotStyle);
app.yLabelText.Layout.Row = 2;
app.yLabelText.Layout.Column = 4;

legendLocationLabel = createLabel(styleGrid, 'Text', '图例位置');
legendLocationLabel.Layout.Row = 4;
legendLocationLabel.Layout.Column = 3;
app.legendLocation = uidropdown(styleGrid, ...
    'Items', {'best', 'northeast', 'northwest', 'southeast', ...
    'southwest', 'north', 'south', 'east', 'west'}, ...
    'Value', app.styleSettings.legendLocation, ...
    'ValueChangedFcn', @applyPlotStyle);
app.legendLocation.Layout.Row = 4;
app.legendLocation.Layout.Column = 4;

axesFontSizeLabel = createLabel(styleGrid, 'Text', '刻度字号');
axesFontSizeLabel.Layout.Row = 3;
axesFontSizeLabel.Layout.Column = 1;
app.axesFontSize = uispinner(styleGrid, 'Limits', [1 100], ...
    'RoundFractionalValues', 'on', 'Value', app.styleSettings.axesFontSize, ...
    'ValueChangedFcn', @applyPlotStyle);
app.axesFontSize.Layout.Row = 3;
app.axesFontSize.Layout.Column = 2;

legendFontSizeLabel = createLabel(styleGrid, 'Text', '图例字号');
legendFontSizeLabel.Layout.Row = 3;
legendFontSizeLabel.Layout.Column = 3;
app.legendFontSize = uispinner(styleGrid, 'Limits', [1 100], ...
    'RoundFractionalValues', 'on', 'Value', app.styleSettings.legendFontSize, ...
    'ValueChangedFcn', @applyPlotStyle);
app.legendFontSize.Layout.Row = 3;
app.legendFontSize.Layout.Column = 4;

legendColumnsLabel = createLabel(styleGrid, 'Text', '图例列数');
legendColumnsLabel.Layout.Row = 4;
legendColumnsLabel.Layout.Column = 1;
app.legendColumns = uispinner(styleGrid, 'Limits', [1 20], ...
    'RoundFractionalValues', 'on', 'Value', app.styleSettings.legendColumns, ...
    'ValueChangedFcn', @applyPlotStyle);
app.legendColumns.Layout.Row = 4;
app.legendColumns.Layout.Column = 2;

app.boldAxisLabels = uicheckbox(styleGrid, ...
    'Text', '轴标题粗体', ...
    'Value', app.styleSettings.boldAxisLabels, ...
    'ValueChangedFcn', @applyPlotStyle);
app.boldAxisLabels.Layout.Row = 5;
app.boldAxisLabels.Layout.Column = 1;

app.showLegend = uicheckbox(styleGrid, ...
    'Text', '显示图例', ...
    'Value', app.styleSettings.showLegend, ...
    'ValueChangedFcn', @applyPlotStyle);
app.showLegend.Layout.Row = 5;
app.showLegend.Layout.Column = 2;

app.showGrid = uicheckbox(styleGrid, ...
    'Text', '显示网格', ...
    'Value', app.styleSettings.showGrid, ...
    'ValueChangedFcn', @applyPlotStyle);
app.showGrid.Layout.Row = 5;
app.showGrid.Layout.Column = 3;

app.useDefaultLegend = uicheckbox(styleGrid, ...
    'Text', '使用默认图例名称', ...
    'Value', app.styleSettings.useDefaultLegend, ...
    'ValueChangedFcn', @applyPlotStyle);
app.useDefaultLegend.Layout.Row = 8;
app.useDefaultLegend.Layout.Column = [1 2];

app.showYLimitLines = uicheckbox(styleGrid, ...
    'Text', '加入上下限 yline', ...
    'Value', app.styleSettings.showYLimitLines, ...
    'ValueChangedFcn', @applyPlotStyle);
app.showYLimitLines.Layout.Row = 7;
app.showYLimitLines.Layout.Column = [1 2];

legendEditorButton = uibutton(styleGrid, ...
    'Text', '编辑图例...', ...
    'ButtonPushedFcn', @openLegendEditor);
legendEditorButton.Layout.Row = 8;
legendEditorButton.Layout.Column = [3 4];

lineWidthLabel = createLabel(styleGrid, 'Text', '曲线线宽');
lineWidthLabel.Layout.Row = 6;
lineWidthLabel.Layout.Column = 1;
app.lineWidth = uispinner(styleGrid, ...
    'Limits', [0.1 20], ...
    'Step', 0.1, ...
    'Value', app.styleSettings.lineWidth, ...
    'ValueChangedFcn', @applyPlotStyle);
app.lineWidth.Layout.Row = 6;
app.lineWidth.Layout.Column = 2;

rendererLabel = createLabel(styleGrid, 'Text', '渲染器');
rendererLabel.Layout.Row = 6;
rendererLabel.Layout.Column = 3;
app.renderer = uidropdown(styleGrid, ...
    'Items', {'opengl', 'painters'}, ...
    'Value', app.styleSettings.renderer, ...
    'ValueChangedFcn', @applyPlotStyle);
app.renderer.Layout.Row = 6;
app.renderer.Layout.Column = 4;

%% 右列下部：绘图坐标轴
plotGrid = uigridlayout(rightGrid, [1 1]);
plotGrid.Padding = [0 0 0 0];
app.axes = uiaxes(plotGrid);
app.axes.Box = 'on';
app.axes.FontSize = 13;
app.axes.XGrid = 'on';
app.axes.YGrid = 'on';

% 弹出式数据预览和图例编辑窗口按需创建并复用。
app.previewFigure = [];
app.previewInfo = [];
app.previewTable = [];
app.legendEditorFigure = [];
app.legendEditorTable = [];

applyPlotStyle();
applyAxisSettings();

refreshFiles();

    % 保存窗口位置和大小，供下次启动恢复。
    function persistWindowPosition(varargin)
        if ~isvalid(app.fig)
            return;
        end
        try
            setpref(app.preferenceGroup, 'WindowPosition', app.fig.Position);
        catch
            % 窗口缩放不应因偏好写入失败而中断。
        end
    end

    % 关闭主窗口时同步清理辅助窗口和选择回写计时器。
    function closeApp(varargin)
        persistDataColumnSettings();
        persistAxisSettings();
        persistWindowPosition();
        persistSmoothPoints();
        if ~isempty(app.previewFigure) && isvalid(app.previewFigure)
            delete(app.previewFigure);
        end
        if ~isempty(app.legendEditorFigure) && isvalid(app.legendEditorFigure)
            delete(app.legendEditorFigure);
        end
        if ~isempty(app.selectionUpdateTimer) && isvalid(app.selectionUpdateTimer)
            stop(app.selectionUpdateTimer);
            delete(app.selectionUpdateTimer);
        end
        delete(app.fig);
    end

    % 单击文件时切换其选中状态，实现无需 Ctrl 的多选。
    function toggleFileSelection(~, event)
        fileName = fileNameFromClick(event);
        if isempty(fileName)
            scheduleSelectionUpdate();
            return;
        end

        selectedIndex = find(strcmp(app.selectedFiles, fileName), 1);
        if isempty(selectedIndex)
            app.selectedFiles{end + 1} = fileName;
        else
            app.selectedFiles(selectedIndex) = [];
        end
        scheduleSelectionUpdate();
    end

    % MATLAB 原生列表行为会在 ClickedFcn 返回后覆盖 Value。
    % 使用单次计时器稍后回写累计选择，确保旧选择不会消失。
    function scheduleSelectionUpdate()
        if isempty(app.selectionUpdateTimer) || ~isvalid(app.selectionUpdateTimer)
            app.selectionUpdateTimer = timer( ...
                'ExecutionMode', 'singleShot', ...
                'StartDelay', 0.05, ...
                'TimerFcn', @applyTrackedSelection);
        elseif strcmp(app.selectionUpdateTimer.Running, 'on')
            stop(app.selectionUpdateTimer);
        end
        start(app.selectionUpdateTimer);
    end

    function applyTrackedSelection(~, ~)
        if isvalid(app.fig) && isvalid(app.fileList)
            app.fileList.Value = app.selectedFiles;
            updateSelectionStatus();
        end
    end

    function updateSelectionStatus()
        if ~isvalid(app.status)
            return;
        end
        selectedCount = numel(app.selectedFiles);
        app.status.FontColor = [0.3 0.3 0.3];
        if selectedCount == 0
            app.status.Text = '未选择作图文件';
        else
            app.status.Text = sprintf('已选择 %d 个作图文件', selectedCount);
        end
    end

    % 数据列更改后立即保存，并沿用现有绘图流程刷新曲线。
    function dataColumnChanged(varargin)
        [saved, saveMessage] = persistDataColumnSettings();
        replotCurrentFiles();
        if ~saved
            app.status.Text = ['数据列已更新，但保存失败：' saveMessage];
            app.status.FontColor = [0.75 0.12 0.12];
        end
    end

    function [success, message] = persistDataColumnSettings()
        success = false;
        message = '';
        try
            app.dataColumnSettings = struct( ...
                'xColumn', app.xColumn.Value, ...
                'yColumn', app.yColumn.Value, ...
                'calibrationXColumn', app.calibrationXColumn.Value, ...
                'calibrationYColumn', app.calibrationYColumn.Value);
            setpref(app.preferenceGroup, 'DataColumnSettings', app.dataColumnSettings);
            success = true;
        catch exception
            message = exception.message;
        end
    end

    % 数据选择或处理参数变化后立即重绘；自动重绘不触发 CSV 导出。
    function replotCurrentFiles(varargin)
        if ~isvalid(app.fig) || ~isvalid(app.axes)
            return;
        end

        selectedNames = app.fileList.Value;
        if ischar(selectedNames) || isstring(selectedNames)
            selectedNames = cellstr(selectedNames);
        end
        if isempty(selectedNames)
            cla(app.axes);
            applyPlotStyle();
            updateYLimitLines();
            app.status.Text = '未选择文件，当前绘图已清空。';
            app.status.FontColor = [0.3 0.3 0.3];
            drawnow limitrate;
            return;
        end

        preservedView = captureAxesView();
        try
            plotSelectedFiles([], [], preservedView);
        catch exception
            app.status.Text = ['自动重绘失败：' exception.message];
            app.status.FontColor = [0.75 0.12 0.12];
        end
        drawnow limitrate;
        updateYLimitLines();
        drawnow limitrate;
    end

    % 保存当前坐标轴视图，避免非绘图设置触发重绘时覆盖用户缩放。
    function view = captureAxesView()
        view = [];
        if ~isvalid(app.axes)
            return;
        end
        try
            view = struct( ...
                'xLim', app.axes.XLim, ...
                'yLim', app.axes.YLim, ...
                'xLimMode', app.axes.XLimMode, ...
                'yLimMode', app.axes.YLimMode);
        catch
            view = [];
        end
    end

    function restoreAxesView(view)
        if isempty(view) || ~isvalid(app.axes)
            return;
        end
        try
            if strcmp(view.xLimMode, 'manual')
                app.axes.XLimMode = 'manual';
                app.axes.XLim = view.xLim;
            else
                app.axes.XLimMode = view.xLimMode;
            end
            if strcmp(view.yLimMode, 'manual')
                app.axes.YLimMode = 'manual';
                app.axes.YLim = view.yLim;
            else
                app.axes.YLimMode = view.yLimMode;
            end
        catch
            % 视图恢复失败不应阻断当前数据重绘。
        end
    end

    function fileName = fileNameFromClick(event)
        fileName = '';
        try
            clickedItem = event.InteractionInformation.Item;
        catch
            clickedItem = [];
        end

        if isnumeric(clickedItem) && isscalar(clickedItem) && ...
                clickedItem >= 1 && clickedItem <= numel(app.fileList.Items)
            fileName = app.fileList.Items{clickedItem};
        elseif ischar(clickedItem) || (isstring(clickedItem) && isscalar(clickedItem))
            fileName = char(clickedItem);
        end
    end

    % 双击文件后读取数值区域，并在可关闭的独立窗口中预览前 5000 行。
    function previewSelectedFile(~, event)
        fileName = fileNameFromClick(event);
        if isempty(fileName) && ~isempty(app.fileList.Value)
            selectedValue = app.fileList.Value;
            if iscell(selectedValue)
                fileName = selectedValue{1};
            else
                fileName = char(selectedValue);
            end
        end

        if isempty(fileName)
            return;
        end

        if ~any(strcmp(app.selectedFiles, fileName))
            app.selectedFiles{end + 1} = fileName;
            app.fileList.Value = app.selectedFiles;
        end

        maximumPreviewRows = 5000;
        filePath = fullfile(app.dataFolder, fileName);
        try
            [previewData, totalRows] = readPreviewData(filePath, maximumPreviewRows);
        catch exception
            app.status.Text = ['数据预览读取失败：' exception.message];
            app.status.FontColor = [0.75 0.12 0.12];
            return;
        end

        if isempty(previewData)
            app.status.Text = ['文件中没有可预览的数值数据：' fileName];
            app.status.FontColor = [0.75 0.12 0.12];
            return;
        end

        if isempty(previewData) || totalRows == 0
            app.status.Text = ['文件中没有可预览的数值数据：' fileName];
            app.status.FontColor = [0.75 0.12 0.12];
            return;
        end

        totalColumns = size(previewData, 2);
        displayedRows = min(totalRows, maximumPreviewRows);
        columnNames = arrayfun(@(columnNumber) sprintf('列 %d', columnNumber), ...
            1:totalColumns, 'UniformOutput', false);
        previewColumnWidths = repmat({90}, 1, totalColumns);

        if isempty(app.previewFigure) || ~isvalid(app.previewFigure)
            mainPosition = app.fig.Position;
            previewWidth = max(700, min(1000, mainPosition(3) - 120));
            previewHeight = max(480, min(700, mainPosition(4) - 120));
            previewPosition = [mainPosition(1) + 60, mainPosition(2) + 60, ...
                previewWidth, previewHeight];

            app.previewFigure = uifigure( ...
                'Name', '数据预览', ...
                'Color', [0.97 0.97 0.97], ...
                'Position', previewPosition);
            previewGrid = uigridlayout(app.previewFigure, [2 1]);
            previewGrid.RowHeight = {30, '1x'};
            previewGrid.Padding = [8 8 8 8];
            app.previewInfo = createLabel(previewGrid, ...
                'Text', '', ...
                'FontColor', [0.3 0.3 0.3]);
            app.previewTable = uitable(previewGrid, ...
                'Data', [], ...
                'ColumnName', {}, ...
                'RowName', 'numbered');
        end

        app.previewFigure.Name = ['数据预览 - ' fileName];
        app.previewTable.Data = previewData(1:displayedRows, :);
        app.previewTable.ColumnName = columnNames;
        app.previewTable.ColumnWidth = previewColumnWidths;
        app.previewInfo.Text = sprintf('%s | 共 %d 行、%d 列，显示前 %d 行', ...
            fileName, totalRows, totalColumns, displayedRows);
        app.previewFigure.Visible = 'on';
        figure(app.previewFigure);
        app.status.Text = ['正在预览：' fileName];
        app.status.FontColor = [0.3 0.3 0.3];
    end

    % 打开可编辑图例表格，仅列出当前选中的绘图文件。
    function openLegendEditor(~, ~)
        selectedNames = app.fileList.Value;
        if ischar(selectedNames) || isstring(selectedNames)
            selectedNames = cellstr(selectedNames);
        end
        if isempty(selectedNames)
            app.status.Text = '请先选择需要编辑图例的文件。';
            app.status.FontColor = [0.75 0.12 0.12];
            return;
        end

        editorData = cell(numel(selectedNames), 2);
        for fileIndex = 1:numel(selectedNames)
            editorData{fileIndex, 1} = selectedNames{fileIndex};
            editorData{fileIndex, 2} = customLegendNameForFile(selectedNames{fileIndex});
        end

        if isempty(app.legendEditorFigure) || ~isvalid(app.legendEditorFigure)
            mainPosition = app.fig.Position;
            editorPosition = [mainPosition(1) + 100, mainPosition(2) + 100, 620, 420];
            app.legendEditorFigure = uifigure( ...
                'Name', '编辑图例', ...
                'Color', [0.97 0.97 0.97], ...
                'Position', editorPosition);
            editorGrid = uigridlayout(app.legendEditorFigure, [2 1]);
            editorGrid.RowHeight = {30, '1x'};
            editorGrid.Padding = [8 8 8 8];
            createLabel(editorGrid, ...
                'Text', '双击“图例名称”单元格即可编辑，留空恢复默认文件名。');
            app.legendEditorTable = uitable(editorGrid, ...
                'ColumnName', {'文件', '图例名称'}, ...
                'ColumnEditable', [false true], ...
                'RowName', 'numbered', ...
                'CellEditCallback', @legendTableEdited);
        end

        app.legendEditorTable.Data = editorData;
        app.legendEditorFigure.Visible = 'on';
        figure(app.legendEditorFigure);
        app.status.Text = sprintf('可编辑 %d 个文件的图例名称', numel(selectedNames));
        app.status.FontColor = [0.3 0.3 0.3];
    end

    % 保存单元格中的图例名称，并立即更新已绘制曲线。
    function legendTableEdited(~, event)
        if isempty(event.Indices) || event.Indices(2) ~= 2
            return;
        end

        rowIndex = event.Indices(1);
        editorData = app.legendEditorTable.Data;
        fileName = editorData{rowIndex, 1};
        newLabel = strtrim(char(string(event.NewData)));
        if isempty(newLabel)
            [~, newLabel] = fileparts(fileName);
        end
        editorData{rowIndex, 2} = newLabel;
        app.legendEditorTable.Data = editorData;

        fileKey = fullfile(app.dataFolder, fileName);
        labelIndex = find(strcmp(app.legendLabels.files, fileKey), 1);
        if isempty(labelIndex)
            app.legendLabels.files{end + 1} = fileKey;
            app.legendLabels.labels{end + 1} = newLabel;
        else
            app.legendLabels.labels{labelIndex} = newLabel;
        end

        try
            setpref(app.preferenceGroup, 'LegendLabels', app.legendLabels);
        catch exception
            app.status.Text = ['图例名称已更新，但保存失败：' exception.message];
            app.status.FontColor = [0.75 0.12 0.12];
            return;
        end

        % 编辑自定义名称后自动切换到自定义图例模式。
        app.useDefaultLegend.Value = false;
        plottedLines = findobj(app.axes, 'Type', 'line');
        for lineIndex = 1:numel(plottedLines)
            lineFile = plottedLines(lineIndex).UserData;
            if (ischar(lineFile) || (isstring(lineFile) && isscalar(lineFile))) && ...
                    strcmp(char(lineFile), fileKey)
                plottedLines(lineIndex).DisplayName = newLabel;
            end
        end
        applyPlotStyle();
        app.status.Text = ['图例名称已保存：' newLabel];
        app.status.FontColor = [0.3 0.3 0.3];
    end

    % 按完整文件路径查找自定义图例；不存在时使用无扩展名文件名。
    function displayName = legendNameForFile(fileName)
        [~, defaultName] = fileparts(fileName);
        if app.useDefaultLegend.Value
            displayName = defaultName;
            return;
        end

        displayName = customLegendNameForFile(fileName);
    end

    % 图例编辑器始终显示已保存的自定义名称，不受默认模式开关影响。
    function displayName = customLegendNameForFile(fileName)
        [~, defaultName] = fileparts(fileName);
        fileKey = fullfile(app.dataFolder, fileName);
        labelIndex = find(strcmp(app.legendLabels.files, fileKey), 1);
        if isempty(labelIndex) || isempty(app.legendLabels.labels{labelIndex})
            displayName = defaultName;
        else
            displayName = app.legendLabels.labels{labelIndex};
        end
    end

    % 将 GUI 中的图形属性实时应用到坐标轴、曲线和图例，并持久化。
    function applyPlotStyle(varargin)
        rendererApplied = true;
        rendererMessage = '';
        if isprop(app.fig, 'Renderer')
            try
                app.fig.Renderer = app.renderer.Value;
            catch exception
                rendererApplied = false;
                rendererMessage = exception.message;
            end
        else
            rendererApplied = false;
            rendererMessage = '当前 MATLAB 图形窗口不支持 Renderer 属性。';
        end

        if app.boldAxisLabels.Value
            labelWeight = 'bold';
        else
            labelWeight = 'normal';
        end

        title(app.axes, app.titleText.Value, 'Interpreter', 'tex');
        xlabel(app.axes, app.xLabelText.Value, ...
            'FontWeight', labelWeight, ...
            'Interpreter', 'none');
        ylabel(app.axes, app.yLabelText.Value, ...
            'FontWeight', labelWeight, ...
            'Interpreter', 'none');
        app.axes.FontSize = app.axesFontSize.Value;

        if app.showGrid.Value
            grid(app.axes, 'on');
        else
            grid(app.axes, 'off');
        end

        plottedLines = findobj(app.axes, 'Type', 'line');
        if ~isempty(plottedLines)
            % 切换默认/自定义模式时同步刷新已有曲线的 DisplayName。
            for lineIndex = 1:numel(plottedLines)
                lineFile = plottedLines(lineIndex).UserData;
                if ischar(lineFile) || (isstring(lineFile) && isscalar(lineFile))
                    [~, lineName, lineExtension] = fileparts(char(lineFile));
                    plottedLines(lineIndex).DisplayName = ...
                        legendNameForFile([lineName lineExtension]);
                end
            end
            set(plottedLines, 'LineWidth', app.lineWidth.Value);
        end
        updateYLimitLines();
        if app.showLegend.Value && ~isempty(plottedLines)
            plotLegend = legend(app.axes, 'show', ...
                'Location', app.legendLocation.Value, ...
                'Interpreter', 'none');
            plotLegend.NumColumns = app.legendColumns.Value;
            plotLegend.FontSize = app.legendFontSize.Value;
        else
            legend(app.axes, 'off');
        end
        refreshCurveChoices();

        app.styleSettings = struct( ...
            'titleText', app.titleText.Value, ...
            'xLabelText', app.xLabelText.Value, ...
            'yLabelText', app.yLabelText.Value, ...
            'axesFontSize', app.axesFontSize.Value, ...
            'legendFontSize', app.legendFontSize.Value, ...
            'legendColumns', app.legendColumns.Value, ...
            'legendLocation', app.legendLocation.Value, ...
            'boldAxisLabels', app.boldAxisLabels.Value, ...
            'showLegend', app.showLegend.Value, ...
            'showGrid', app.showGrid.Value, ...
            'useDefaultLegend', app.useDefaultLegend.Value, ...
            'showYLimitLines', app.showYLimitLines.Value, ...
            'lineWidth', app.lineWidth.Value, ...
            'renderer', app.renderer.Value);

        try
            setpref(app.preferenceGroup, 'StyleSettings', app.styleSettings);
        catch exception
            app.status.Text = ['图形属性已更新，但保存失败：' exception.message];
            app.status.FontColor = [0.75 0.12 0.12];
            return;
        end

        if rendererApplied
            app.status.Text = '图形属性已更新并保存';
            app.status.FontColor = [0.3 0.3 0.3];
        else
            app.status.Text = ['渲染器设置未生效：' rendererMessage];
            app.status.FontColor = [0.75 0.12 0.12];
        end
    end

    % 扫描当前目录中的支持格式，并刷新绘图和校准文件列表。
    function refreshFiles(varargin)
        patterns = {'*.txt', '*.csv', '*.dat'};
        files = struct([]);
        for patternIndex = 1:numel(patterns)
            files = [files; dir(fullfile(app.dataFolder, patterns{patternIndex}))]; %#ok<AGROW>
        end

        names = unique({files.name}, 'stable');
        previousCalibration = '';
        if ~isempty(app.calibrationFile.Items)
            previousCalibration = app.calibrationFile.Value;
        end

        app.fileList.Items = names;
        app.selectedFiles = {};
        app.fileList.Value = {};
        if isempty(names)
            app.calibrationFile.Items = {'(无可用文件)'};
            app.calibrationFile.Value = '(无可用文件)';
            app.calibrationFile.Enable = 'off';
        else
            app.calibrationFile.Items = names;
            if any(strcmp(names, previousCalibration))
                app.calibrationFile.Value = previousCalibration;
            elseif any(strcmpi(names, app.defaultCalibrationName))
                defaultIndex = find(strcmpi(names, app.defaultCalibrationName), 1);
                app.calibrationFile.Value = names{defaultIndex};
            else
                app.calibrationFile.Value = names{1};
            end
        end
        setCalibrationEnabled();
        app.folderField.Value = app.dataFolder;
        app.status.Text = sprintf('找到 %d 个可绘图文件', numel(names));
        app.status.FontColor = [0.3 0.3 0.3];
    end

    % 根据校准复选框状态启用或禁用校准文件与列设置。
    function setCalibrationEnabled(varargin)
        if isempty(app.fileList.Items)
            app.calibrationFile.Enable = 'off';
            app.calibrationXColumn.Enable = 'off';
            app.calibrationYColumn.Enable = 'off';
        elseif app.subtractCalibration.Value
            app.calibrationFile.Enable = 'on';
            app.calibrationXColumn.Enable = 'on';
            app.calibrationYColumn.Enable = 'on';
        else
            app.calibrationFile.Enable = 'off';
            app.calibrationXColumn.Enable = 'off';
            app.calibrationYColumn.Enable = 'off';
        end
        replotCurrentFiles();
    end

    % 平滑关闭时禁用点数输入；设置在下次绘图或曲线相减时生效。
    function setSmoothEnabled(varargin)
        if app.enableSmooth.Value
            app.smoothPoints.Enable = 'on';
        else
            app.smoothPoints.Enable = 'off';
        end
        replotCurrentFiles();
    end

    % 保存平滑窗口点数，并立即重绘当前数据。
    function smoothPointsChanged(varargin)
        [saved, saveMessage] = persistSmoothPoints();
        replotCurrentFiles();
        if ~saved
            app.status.Text = ['平滑点数已更新，但保存失败：' saveMessage];
            app.status.FontColor = [0.75 0.12 0.12];
        end
    end

    function [success, message] = persistSmoothPoints()
        success = false;
        message = '';
        try
            app.smoothPointsValue = max(1, round(app.smoothPoints.Value));
            setpref(app.preferenceGroup, 'SmoothPoints', app.smoothPointsValue);
            success = true;
        catch exception
            message = exception.message;
        end
    end

    % 从当前坐标轴提取曲线并同步到相减和保存下拉列表。
    function refreshCurveChoices(varargin)
        previousA = app.subtractCurveA.Value;
        previousB = app.subtractCurveB.Value;
        previousSaveCurve = app.saveCurve.Value;
        plottedLines = flipud(findobj(app.axes, 'Type', 'line'));

        if isempty(plottedLines)
            app.currentCurveHandles = gobjects(0);
            app.currentCurveLabels = {};
            app.subtractCurveA.Items = {'(暂无曲线)'};
            app.subtractCurveB.Items = {'(暂无曲线)'};
            app.saveCurve.Items = {'(暂无曲线)'};
            app.subtractCurveA.Enable = 'off';
            app.subtractCurveB.Enable = 'off';
            app.saveCurve.Enable = 'off';
            app.curveSubtractButton.Enable = 'off';
            app.saveProcessedButton.Enable = 'off';
            return;
        end

        curveLabels = cell(1, numel(plottedLines));
        for lineIndex = 1:numel(plottedLines)
            displayName = strtrim(char(string(plottedLines(lineIndex).DisplayName)));
            if isempty(displayName)
                displayName = sprintf('曲线 %d', lineIndex);
            end
            curveLabels{lineIndex} = sprintf('%d: %s', lineIndex, displayName);
        end

        app.currentCurveHandles = plottedLines;
        app.currentCurveLabels = curveLabels;
        app.subtractCurveA.Items = curveLabels;
        app.subtractCurveB.Items = curveLabels;
        app.saveCurve.Items = curveLabels;
        app.subtractCurveA.Enable = 'on';
        app.subtractCurveB.Enable = 'on';
        app.saveCurve.Enable = 'on';
        app.saveProcessedButton.Enable = 'on';

        if any(strcmp(curveLabels, previousA))
            app.subtractCurveA.Value = previousA;
        else
            app.subtractCurveA.Value = curveLabels{1};
        end
        if any(strcmp(curveLabels, previousB))
            app.subtractCurveB.Value = previousB;
        elseif numel(curveLabels) >= 2
            app.subtractCurveB.Value = curveLabels{2};
        else
            app.subtractCurveB.Value = curveLabels{1};
        end
        if any(strcmp(curveLabels, previousSaveCurve))
            app.saveCurve.Value = previousSaveCurve;
        else
            app.saveCurve.Value = curveLabels{1};
        end

        if numel(plottedLines) >= 2
            app.curveSubtractButton.Enable = 'on';
        else
            app.curveSubtractButton.Enable = 'off';
        end
    end

    % 对当前显示曲线执行 A-B；B 曲线插值到 A 曲线的重叠 X 点。
    function plotCurveDifference(~, ~)
        refreshCurveChoices();
        if numel(app.currentCurveHandles) < 2
            app.status.Text = '当前至少需要两条已绘制曲线才能相减。';
            app.status.FontColor = [0.75 0.12 0.12];
            return;
        end

        curveAIndex = find(strcmp(app.currentCurveLabels, app.subtractCurveA.Value), 1);
        curveBIndex = find(strcmp(app.currentCurveLabels, app.subtractCurveB.Value), 1);
        if isempty(curveAIndex) || isempty(curveBIndex)
            app.status.Text = '曲线列表已变化，请刷新后重新选择。';
            app.status.FontColor = [0.75 0.12 0.12];
            return;
        end
        if curveAIndex == curveBIndex
            app.status.Text = '曲线 A 与曲线 B 不能选择同一条曲线。';
            app.status.FontColor = [0.75 0.12 0.12];
            return;
        end

        curveA = app.currentCurveHandles(curveAIndex);
        curveB = app.currentCurveHandles(curveBIndex);
        try
            [xA, yA] = cleanCurveData(curveA.XData, curveA.YData);
            [xB, yB] = cleanCurveData(curveB.XData, curveB.YData);
            if numel(xA) < 2 || numel(xB) < 2
                error('每条曲线至少需要两个有效且不同的 X 点。');
            end

            yBAtA = interp1(xB, yB, xA, 'linear', NaN);
            validRows = isfinite(yBAtA);
            xDifference = xA(validRows);
            yDifference = yA(validRows) - yBAtA(validRows);
            if isempty(xDifference)
                error('所选曲线没有重叠的 X 轴范围。');
            end
            yDifference = smoothCurveData(yDifference);

            nameA = char(string(curveA.DisplayName));
            nameB = char(string(curveB.DisplayName));
            differenceName = sprintf('%s - %s', nameA, nameB);
            colorMap = lines(numel(app.currentCurveHandles) + 1);
            differenceMetadata = struct( ...
                'Kind', 'curveDifference', ...
                'SourceA', nameA, ...
                'SourceB', nameB);

            hold(app.axes, 'on');
            plot(app.axes, xDifference, yDifference, ...
                'Color', colorMap(end, :), ...
                'LineStyle', '--', ...
                'LineWidth', app.lineWidth.Value, ...
                'DisplayName', differenceName, ...
                'UserData', differenceMetadata);
            hold(app.axes, 'off');
            applyPlotStyle();
            applyAxisSettings();
            drawnow limitrate;
            updateYLimitLines();
        catch exception
            hold(app.axes, 'off');
            app.status.Text = ['曲线相减失败：' exception.message];
            app.status.FontColor = [0.75 0.12 0.12];
            return;
        end

        app.status.Text = ['曲线相减完成：' differenceName];
        app.status.FontColor = [0.05 0.48 0.18];
    end

    % 删除无效点、按 X 升序排列并去除重复 X，便于可靠插值。
    function [xData, yData] = cleanCurveData(xData, yData)
        xData = xData(:);
        yData = yData(:);
        if numel(xData) ~= numel(yData)
            error('曲线的 X/Y 数据点数不一致。');
        end
        validRows = isfinite(xData) & isfinite(yData);
        xData = xData(validRows);
        yData = yData(validRows);
        [xData, sortIndex] = sort(xData);
        yData = yData(sortIndex);
        [xData, uniqueIndex] = unique(xData, 'stable');
        yData = yData(uniqueIndex);
    end

    % 使用用户指定的移动平均窗口执行 smooth；窗口不会超过有效点数。
    function yData = smoothCurveData(yData)
        if ~app.enableSmooth.Value || isempty(yData)
            return;
        end
        smoothWindow = min(numel(yData), max(1, round(app.smoothPoints.Value)));
        if smoothWindow > 1
            yData = smoothdata(yData, 'movmean', smoothWindow);
        end
    end

    % 优先使用可编辑文件名；留空时根据所选曲线生成名称。
    function outputName = processedOutputName(defaultName)
        customName = strtrim(char(string(app.processedFileName.Value)));
        customName = regexprep(customName, '(?i)\.csv$', '');
        if isempty(customName)
            outputName = [char(string(defaultName)) '_processed'];
        else
            outputName = customName;
        end
    end

    % 将下拉框选中的当前显示曲线保存为 CSV。
    function saveCurrentProcessedCurves(~, ~)
        refreshCurveChoices();
        if isempty(app.currentCurveHandles)
            app.status.Text = '当前没有可保存的曲线。';
            app.status.FontColor = [0.75 0.12 0.12];
            return;
        end

        curveIndex = find(strcmp(app.currentCurveLabels, app.saveCurve.Value), 1);
        if isempty(curveIndex)
            app.status.Text = '保存曲线列表已变化，请重新选择。';
            app.status.FontColor = [0.75 0.12 0.12];
            return;
        end

        selectedCurve = app.currentCurveHandles(curveIndex);
        curveName = strtrim(char(string(selectedCurve.DisplayName)));
        if isempty(curveName)
            curveName = sprintf('curve_%d', curveIndex);
        end
        try
            xData = selectedCurve.XData(:);
            yData = selectedCurve.YData(:);
            if numel(xData) ~= numel(yData)
                error('曲线的 X/Y 数据点数不一致。');
            end
            xLimits = app.axes.XLim;
            yLimits = app.axes.YLim;
            if numel(xLimits) ~= 2 || numel(yLimits) ~= 2 || ...
                    any(~isfinite(xLimits)) || any(~isfinite(yLimits)) || ...
                    xLimits(1) >= xLimits(2) || yLimits(1) >= yLimits(2)
                error('当前图窗坐标范围无效。');
            end

            % 只保存当前图窗可见范围内的数据点，不保存坐标范围外的完整曲线。
            validRows = isfinite(xData) & isfinite(yData) & ...
                xData >= xLimits(1) & xData <= xLimits(2) & ...
                yData >= yLimits(1) & yData <= yLimits(2);
            xData = xData(validRows);
            yData = yData(validRows);
            if isempty(xData)
                error('当前图窗范围内没有有效的 X/Y 数据点。');
            end
            outputName = processedOutputName(curveName);
            outputFile = saveProcessedCurveData(outputName, xData, yData);
            app.status.Text = sprintf('已保存图窗可见数据（%d 点）：%s', ...
                numel(xData), outputFile);
            app.status.FontColor = [0.05 0.48 0.18];
        catch exception
            app.status.Text = ['曲线保存失败：' exception.message];
            app.status.FontColor = [0.75 0.12 0.12];
        end
    end

    % 将处理后的 X/Y 两列直接写入当前数据目录。
    function outputFile = saveProcessedCurveData(outputName, xData, yData)
        if numel(xData) ~= numel(yData)
            error('处理后曲线的 X/Y 数据点数不一致。');
        end
        outputFolder = app.dataFolder;
        if ~isfolder(outputFolder)
            [created, message] = mkdir(outputFolder);
            if ~created
                error('无法创建保存目录：%s', message);
            end
        end

        safeName = strtrim(char(string(outputName)));
        safeName = regexprep(safeName, '[<>:"/\\|?*]', '_');
        safeName = regexprep(safeName, '\s+', '_');
        if isempty(safeName)
            safeName = 'processed_curve';
        end
        maximumNameLength = 120;
        safeName = safeName(1:min(numel(safeName), maximumNameLength));

        outputBase = fullfile(outputFolder, safeName);
        outputFile = [outputBase '.csv'];
        fileNumber = 2;
        while isfile(outputFile)
            outputFile = sprintf('%s_%d.csv', outputBase, fileNumber);
            fileNumber = fileNumber + 1;
        end

        processedTable = table(xData(:), yData(:), ...
            'VariableNames', {'X', 'Y'});
        writetable(processedTable, outputFile);
    end

    % 数据缩放系数按乘法应用到 X/Y 数据；校准曲线和待绘曲线使用同一系数。
    function [xScaleFactor, yScaleFactor] = dataScaleFactors()
        xScaleFactor = app.xDataScale.Value;
        yScaleFactor = app.yDataScale.Value;
        if ~(isnumeric(xScaleFactor) && isscalar(xScaleFactor) && isfinite(xScaleFactor))
            error('X 缩放系数必须是有限数值。');
        end
        if ~(isnumeric(yScaleFactor) && isscalar(yScaleFactor) && isfinite(yScaleFactor))
            error('Y 缩放系数必须是有限数值。');
        end
    end

    function dataScaleChanged(~, ~)
        try
            [xScaleFactor, yScaleFactor] = dataScaleFactors();
        catch exception
            app.xDataScale.Value = app.dataScaleSettings.xFactor;
            app.yDataScale.Value = app.dataScaleSettings.yFactor;
            app.status.Text = ['数据缩放设置无效：' exception.message];
            app.status.FontColor = [0.75 0.12 0.12];
            return;
        end

        app.dataScaleSettings = struct( ...
            'xFactor', xScaleFactor, ...
            'yFactor', yScaleFactor);
        try
            setpref(app.preferenceGroup, 'DataScaleSettings', app.dataScaleSettings);
        catch exception
            app.status.Text = ['数据缩放已应用，但保存失败：' exception.message];
            app.status.FontColor = [0.75 0.12 0.12];
            return;
        end

        app.status.Text = sprintf('数据缩放已设置：X × %.6g，Y × %.6g', ...
            xScaleFactor, yScaleFactor);
        app.status.FontColor = [0.05 0.48 0.18];
        replotCurrentFiles();
    end

    % Y 轴补偿只影响绘图结果，不修改原始文件和数据预览。
    function yCompensationChanged(~, ~)
        newCompensation = app.yCompensation.Value;
        if ~(isnumeric(newCompensation) && isscalar(newCompensation) && ...
                isfinite(newCompensation))
            app.yCompensation.Value = app.appliedYCompensation;
            app.status.Text = 'Y 轴补偿必须是有限数值。';
            app.status.FontColor = [0.75 0.12 0.12];
            return;
        end

        compensationDelta = newCompensation - app.appliedYCompensation;
        plottedLines = findobj(app.axes, 'Type', 'line');
        for lineIndex = 1:numel(plottedLines)
            lineSource = plottedLines(lineIndex).UserData;
            if ischar(lineSource) || (isstring(lineSource) && isscalar(lineSource))
                plottedLines(lineIndex).YData = ...
                    plottedLines(lineIndex).YData + compensationDelta;
            end
        end
        app.appliedYCompensation = newCompensation;

        try
            setpref(app.preferenceGroup, 'YCompensation', newCompensation);
            app.status.Text = sprintf('Y 轴补偿已设置为 %.6g dB', newCompensation);
            app.status.FontColor = [0.05 0.48 0.18];
        catch exception
            app.status.Text = ['Y 轴补偿已应用，但保存失败：' exception.message];
            app.status.FontColor = [0.75 0.12 0.12];
        end
        drawnow limitrate;
        updateYLimitLines();
        drawnow limitrate;
    end

    function chooseFolder(~, ~)
        selectedFolder = uigetdir(app.dataFolder, '选择数据目录');
        if isequal(selectedFolder, 0)
            return;
        end
        app.dataFolder = selectedFolder;
        refreshFiles();
    end

    function selectAllFiles(~, ~)
        app.selectedFiles = app.fileList.Items;
        app.fileList.Value = app.selectedFiles;
        updateSelectionStatus();
    end

    function clearSelection(~, ~)
        app.selectedFiles = {};
        app.fileList.Value = {};
        updateSelectionStatus();
    end

    function clearAxisLimits(varargin)
        app.autoScaleOnPlot.Value = true;
        app.xMin.Value = [];
        app.xMax.Value = [];
        app.yMin.Value = [];
        app.yMax.Value = [];
        applyAxisSettings();
    end

    function autoScaleChanged(varargin)
        if app.autoScaleOnPlot.Value
            clearAxisLimits();
        else
            applyAxisSettings();
        end
    end

    function manualAxisLimitChanged(varargin)
        app.autoScaleOnPlot.Value = false;
        applyAxisSettings();
    end

    % 实时应用线性/对数尺度和坐标范围；自动模式下 X 轴使用 tight。
    function success = applyAxisSettings(varargin)
        success = true;
        try
            app.axes.XScale = app.xScale.Value;
            app.axes.YScale = app.yScale.Value;
            applyOneLimit('x', app.xMin.Value, app.xMax.Value);
            applyOneLimit('y', app.yMin.Value, app.yMax.Value);
            if app.autoScaleOnPlot.Value && isempty(app.xMin.Value) && isempty(app.xMax.Value)
                xlim(app.axes, 'tight');
            end
            updateYLimitLines();
            [saved, saveMessage] = persistAxisSettings();
            if saved
                app.status.Text = '坐标设置已更新并保存';
                app.status.FontColor = [0.3 0.3 0.3];
            else
                app.status.Text = ['坐标设置已更新，但保存失败：' saveMessage];
                app.status.FontColor = [0.75 0.12 0.12];
            end
        catch exception
            success = false;
            app.status.Text = ['坐标设置无效：' exception.message];
            app.status.FontColor = [0.75 0.12 0.12];
        end
    end

    % 将坐标范围、尺度和自动缩放状态保存到 MATLAB 用户偏好。
    function [success, message] = persistAxisSettings()
        success = false;
        message = '';
        try
            app.axisSettings = struct( ...
                'xMin', app.xMin.Value, ...
                'xMax', app.xMax.Value, ...
                'yMin', app.yMin.Value, ...
                'yMax', app.yMax.Value, ...
                'xScale', app.xScale.Value, ...
                'yScale', app.yScale.Value, ...
                'autoScaleOnPlot', logical(app.autoScaleOnPlot.Value));
            setpref(app.preferenceGroup, 'AxisSettings', app.axisSettings);
            success = true;
        catch exception
            message = exception.message;
        end
    end

    % 单独设置一条坐标轴；留空表示由 MATLAB 自动确定范围。
    function applyOneLimit(axisName, minimumValue, maximumValue)
        if isempty(minimumValue) && isempty(maximumValue)
            if axisName == 'x'
                app.axes.XLimMode = 'auto';
            else
                app.axes.YLimMode = 'auto';
            end
            return;
        end

        currentLimit = app.axes.([upper(axisName) 'Lim']);
        if isempty(minimumValue)
            minimumValue = currentLimit(1);
        end
        if isempty(maximumValue)
            maximumValue = currentLimit(2);
        end
        if ~isfinite(minimumValue) || ~isfinite(maximumValue) || minimumValue >= maximumValue
            error('%s 轴最小值必须小于最大值。', upper(axisName));
        end
        app.axes.([upper(axisName) 'Lim']) = [minimumValue maximumValue];
    end

    % 根据当前显示曲线数据的最大值和最小值实时绘制虚线。
    function updateYLimitLines(varargin)
        if ~isempty(app.yLimitLineHandles)
            validHandles = app.yLimitLineHandles(isvalid(app.yLimitLineHandles));
            if ~isempty(validHandles)
                delete(validHandles);
            end
        end
        app.yLimitLineHandles = gobjects(0);

        if ~isvalid(app.axes) || ~app.showYLimitLines.Value
            return;
        end

        xLimits = app.axes.XLim;
        yLimits = app.axes.YLim;
        if numel(xLimits) ~= 2 || numel(yLimits) ~= 2 || ...
                any(~isfinite(xLimits)) || any(~isfinite(yLimits)) || ...
                xLimits(1) >= xLimits(2) || yLimits(1) >= yLimits(2)
            return;
        end

        plottedLines = findobj(app.axes, 'Type', 'line');
        visibleYData = [];
        for lineIndex = 1:numel(plottedLines)
            lineXData = plottedLines(lineIndex).XData(:);
            lineYData = plottedLines(lineIndex).YData(:);
            pointCount = min(numel(lineXData), numel(lineYData));
            if pointCount == 0
                continue;
            end
            lineXData = lineXData(1:pointCount);
            lineYData = lineYData(1:pointCount);
            visibleMask = isfinite(lineXData) & isfinite(lineYData) & ...
                lineXData >= xLimits(1) & lineXData <= xLimits(2) & ...
                lineYData >= yLimits(1) & lineYData <= yLimits(2);
            if any(visibleMask)
                visibleYData = [visibleYData; lineYData(visibleMask)]; %#ok<AGROW>
            end
        end
        if isempty(visibleYData)
            return;
        end

        % yline1 对应当前窗口内可见数据的 ymax，yline2 对应 ymin。
        lineColors = [0.49 0.18 0.56; 0.85 0.33 0.10];
        ymax = max(visibleYData);
        ymin = min(visibleYData);
        hold(app.axes, 'on');
        app.yLimitLineHandles(1) = yline(app.axes, ymax, ...
                '--', sprintf('%.6g', ymax), ...
                'Color', lineColors(1, :), ...
                'LineWidth', max(1, app.lineWidth.Value), ...
                'LabelHorizontalAlignment', 'left', ...
                'LabelVerticalAlignment', 'top', ...
                'HandleVisibility', 'off');
        app.yLimitLineHandles(2) = yline(app.axes, ymin, ...
                '--', sprintf('%.6g', ymin), ...
                'Color', lineColors(2, :), ...
                'LineWidth', max(1, app.lineWidth.Value), ...
                'LabelHorizontalAlignment', 'left', ...
                'LabelVerticalAlignment', 'bottom', ...
                'HandleVisibility', 'off');
        hold(app.axes, 'off');
    end

    % 读取所选文件、按需扣除校准曲线，并绘制所有有效数据。
    function plotSelectedFiles(~, ~, preservedView)
        if nargin < 3
            preservedView = [];
        end
        selectedNames = app.fileList.Value;
        if ischar(selectedNames) || isstring(selectedNames)
            selectedNames = cellstr(selectedNames);
        end
        if isempty(selectedNames)
            app.status.Text = '请先在左侧选择至少一个文件。';
            app.status.FontColor = [0.75 0.12 0.12];
            return;
        end

        xColumn = app.xColumn.Value;
        yColumn = app.yColumn.Value;
        calibrationXColumn = app.calibrationXColumn.Value;
        calibrationYColumn = app.calibrationYColumn.Value;
        calibrationX = [];
        calibrationY = [];
        try
            [xScaleFactor, yScaleFactor] = dataScaleFactors();
        catch exception
            app.status.Text = ['数据缩放设置无效：' exception.message];
            app.status.FontColor = [0.75 0.12 0.12];
            return;
        end

        if app.subtractCalibration.Value
            % 校准文件可使用独立的 X/Y 列，随后按 X 值插值到待绘数据。
            calibrationName = app.calibrationFile.Value;
            calibrationFile = fullfile(app.dataFolder, calibrationName);
            if ~isfile(calibrationFile)
                app.status.Text = ['未找到校准文件：' calibrationName];
                app.status.FontColor = [0.75 0.12 0.12];
                return;
            end
            try
                calibrationData = readNumericData( ...
                    calibrationFile, calibrationXColumn, calibrationYColumn);
                calibrationX = calibrationData(:, calibrationXColumn) * xScaleFactor;
                calibrationY = calibrationData(:, calibrationYColumn) * yScaleFactor;
                [calibrationX, sortIndex] = sort(calibrationX);
                calibrationY = calibrationY(sortIndex);
                [calibrationX, uniqueIndex] = unique(calibrationX, 'stable');
                calibrationY = calibrationY(uniqueIndex);
                if numel(calibrationX) < 2
                    error('校准曲线至少需要两个有效且不同的 X 点。');
                end
            catch exception
                app.status.Text = ['校准文件读取失败：' exception.message];
                app.status.FontColor = [0.75 0.12 0.12];
                return;
            end
        end

        cla(app.axes);
        hold(app.axes, 'on');
        colors = lines(numel(selectedNames));
        plottedCount = 0;
        skippedMessages = {};

        for fileIndex = 1:numel(selectedNames)
            fileName = selectedNames{fileIndex};
            filePath = fullfile(app.dataFolder, fileName);
            try
                numericData = readNumericData(filePath, xColumn, yColumn);
                xData = numericData(:, xColumn) * xScaleFactor;
                yData = numericData(:, yColumn) * yScaleFactor;

                if app.subtractCalibration.Value
                    % 只保留与校准曲线 X 范围重叠的点，避免外插引入误差。
                    calibrationAtX = interp1(calibrationX, calibrationY, xData, 'linear', NaN);
                    validRows = isfinite(calibrationAtX);
                    xData = xData(validRows);
                    yData = yData(validRows) - calibrationAtX(validRows);
                    if isempty(xData)
                        error('与校准数据没有重叠的 X 轴范围。');
                    end
                end

                yData = yData + app.yCompensation.Value;
                yData = smoothCurveData(yData);

                displayName = legendNameForFile(fileName);
                plot(app.axes, xData, yData, ...
                    'Color', colors(fileIndex, :), ...
                    'LineWidth', app.lineWidth.Value, ...
                    'DisplayName', displayName, ...
                    'UserData', filePath);
                plottedCount = plottedCount + 1;
            catch exception
                skippedMessages{end + 1} = sprintf('%s：%s', fileName, exception.message); %#ok<AGROW>
            end
        end

        hold(app.axes, 'off');
        app.appliedYCompensation = app.yCompensation.Value;
        applyPlotStyle();

        if isempty(preservedView)
            if app.autoScaleOnPlot.Value
                app.xMin.Value = [];
                app.xMax.Value = [];
                app.yMin.Value = [];
                app.yMax.Value = [];
                app.axes.XLimMode = 'auto';
                app.axes.YLimMode = 'auto';
            end
            axisSettingsApplied = applyAxisSettings();
        else
            restoreAxesView(preservedView);
            axisSettingsApplied = true;
        end
        % Refresh y-limit lines after the final YLim is established.
        drawnow limitrate;
        updateYLimitLines();
        if axisSettingsApplied
            app.status.Text = sprintf('已绘制 %d/%d 个文件', plottedCount, numel(selectedNames));
            app.status.FontColor = [0.3 0.3 0.3];
        end
        if ~isempty(skippedMessages)
            app.status.Text = sprintf('已绘制 %d/%d；问题：%s', ...
                plottedCount, numel(selectedNames), strjoin(skippedMessages, '；'));
            app.status.FontColor = [0.75 0.12 0.12];
        end
    end

    % 读取数值矩阵，并过滤所选 X/Y 列中包含 NaN/Inf 的行。
    function numericData = readNumericData(filePath, xColumn, yColumn)
        numericData = readmatrix(filePath);
        requiredColumn = max(xColumn, yColumn);
        if isempty(numericData) || size(numericData, 2) < requiredColumn
            error('文件不足 %d 列。', requiredColumn);
        end
        validRows = isfinite(numericData(:, xColumn)) & isfinite(numericData(:, yColumn));
        numericData = numericData(validRows, :);
        if isempty(numericData)
            error('所选 X/Y 列中没有有效数值。');
        end
    end
end

function [previewData, totalRows] = readPreviewData(filePath, maximumRows)
% 仅解析预览所需的前若干行，同时统计有效数值行，避免整文件矩阵化。
previewData = zeros(0, 0);
totalRows = 0;
fileIdentifier = fopen(filePath, 'r');
if fileIdentifier < 0
    error('无法打开文件：%s', filePath);
end
cleanupObject = onCleanup(@() fclose(fileIdentifier)); %#ok<NASGU>

while true
    lineText = fgetl(fileIdentifier);
    if ~ischar(lineText)
        break;
    end

    rowValues = parsePreviewLine(lineText);
    if isempty(rowValues) || ~any(isfinite(rowValues))
        continue;
    end

    totalRows = totalRows + 1;
    if size(previewData, 1) >= maximumRows
        continue;
    end

    if size(previewData, 2) < numel(rowValues)
        previewData(:, end + 1:numel(rowValues)) = NaN;
    end
    paddedRow = NaN(1, size(previewData, 2));
    paddedRow(1:numel(rowValues)) = rowValues;
    previewData(end + 1, :) = paddedRow; %#ok<AGROW>
end
end

function rowValues = parsePreviewLine(lineText)
lineText = strtrim(lineText);
if isempty(lineText)
    rowValues = [];
    return;
end

if contains(lineText, sprintf('\t'))
    tokens = regexp(lineText, '\t', 'split');
elseif contains(lineText, ',')
    tokens = strsplit(lineText, ',');
elseif contains(lineText, ';')
    tokens = strsplit(lineText, ';');
else
    tokens = regexp(lineText, '\s+', 'split');
end

rowValues = NaN(1, numel(tokens));
for tokenIndex = 1:numel(tokens)
    tokenText = strtrim(tokens{tokenIndex});
    if isempty(tokenText)
        continue;
    end
    tokenText = strrep(strrep(tokenText, 'D', 'E'), 'd', 'e');
    rowValues(tokenIndex) = str2double(tokenText);
end
end

function labelComponent = createLabel(varargin)
% 使用 MATLAB 公开的 uilabel 接口，避免内部组件工厂在不同版本中参数不兼容。
labelComponent = uilabel(varargin{:});
end

function settings = loadDataColumnSettings(preferenceGroup)
% 恢复主数据和校准数据的 X/Y 列号；无效值使用原默认列。
settings = struct( ...
    'xColumn', 1, ...
    'yColumn', 3, ...
    'calibrationXColumn', 1, ...
    'calibrationYColumn', 3);

if ~ispref(preferenceGroup, 'DataColumnSettings')
    return;
end

try
    savedSettings = getpref(preferenceGroup, 'DataColumnSettings');
catch
    return;
end
if ~isstruct(savedSettings)
    return;
end

settingNames = fieldnames(settings);
for settingIndex = 1:numel(settingNames)
    settingName = settingNames{settingIndex};
    if isfield(savedSettings, settingName)
        savedValue = savedSettings.(settingName);
        if isnumeric(savedValue) && isscalar(savedValue) && ...
                isfinite(savedValue) && savedValue >= 1 && savedValue == round(savedValue)
            settings.(settingName) = savedValue;
        end
    end
end
end

function settings = loadDataScaleSettings(preferenceGroup)
% 读取持久化数据缩放系数；缺失或损坏时恢复为 1。
settings = struct('xFactor', 1, 'yFactor', 1);
if ~ispref(preferenceGroup, 'DataScaleSettings')
    return;
end
try
    savedSettings = getpref(preferenceGroup, 'DataScaleSettings');
catch
    return;
end
if ~isstruct(savedSettings)
    return;
end
if isfield(savedSettings, 'xFactor') && isnumeric(savedSettings.xFactor) && ...
        isscalar(savedSettings.xFactor) && isfinite(savedSettings.xFactor)
    settings.xFactor = savedSettings.xFactor;
end
if isfield(savedSettings, 'yFactor') && isnumeric(savedSettings.yFactor) && ...
        isscalar(savedSettings.yFactor) && isfinite(savedSettings.yFactor)
    settings.yFactor = savedSettings.yFactor;
end
end

function value = loadSmoothPoints(preferenceGroup)
% 读取持久化平滑窗口点数；缺失或损坏时恢复为 5。
value = 5;
if ~ispref(preferenceGroup, 'SmoothPoints')
    return;
end
try
    savedValue = getpref(preferenceGroup, 'SmoothPoints');
    if isnumeric(savedValue) && isscalar(savedValue) && ...
            isfinite(savedValue) && savedValue >= 1
        value = round(savedValue);
    end
catch
    value = 5;
end
end

function settings = loadAxisSettings(preferenceGroup)
% 恢复坐标范围、尺度和自动缩放状态；无效偏好回退到自动范围。
settings = struct( ...
    'xMin', [], ...
    'xMax', [], ...
    'yMin', [], ...
    'yMax', [], ...
    'xScale', 'linear', ...
    'yScale', 'linear', ...
    'autoScaleOnPlot', true);

if ~ispref(preferenceGroup, 'AxisSettings')
    return;
end

try
    savedSettings = getpref(preferenceGroup, 'AxisSettings');
catch
    return;
end
if ~isstruct(savedSettings)
    return;
end

limitNames = {'xMin', 'xMax', 'yMin', 'yMax'};
for limitIndex = 1:numel(limitNames)
    limitName = limitNames{limitIndex};
    if isfield(savedSettings, limitName)
        savedLimit = savedSettings.(limitName);
        if isempty(savedLimit) || (isnumeric(savedLimit) && isscalar(savedLimit) && isfinite(savedLimit))
            settings.(limitName) = savedLimit;
        end
    end
end

scaleNames = {'xScale', 'yScale'};
for scaleIndex = 1:numel(scaleNames)
    scaleName = scaleNames{scaleIndex};
    if isfield(savedSettings, scaleName)
        savedScale = savedSettings.(scaleName);
        if (ischar(savedScale) || (isstring(savedScale) && isscalar(savedScale))) && ...
                any(strcmp(char(savedScale), {'linear', 'log'}))
            settings.(scaleName) = char(savedScale);
        end
    end
end

if isfield(savedSettings, 'autoScaleOnPlot')
    savedAutoScale = savedSettings.autoScaleOnPlot;
    if (islogical(savedAutoScale) && isscalar(savedAutoScale)) || ...
            (isnumeric(savedAutoScale) && isscalar(savedAutoScale) && any(savedAutoScale == [0 1]))
        settings.autoScaleOnPlot = logical(savedAutoScale);
    end
end

if ~isempty(settings.xMin) && ~isempty(settings.xMax) && settings.xMin >= settings.xMax
    settings.xMin = [];
    settings.xMax = [];
end
if ~isempty(settings.yMin) && ~isempty(settings.yMax) && settings.yMin >= settings.yMax
    settings.yMin = [];
    settings.yMax = [];
end
if strcmp(settings.xScale, 'log') && ...
        ((~isempty(settings.xMin) && settings.xMin <= 0) || ...
        (~isempty(settings.xMax) && settings.xMax <= 0))
    settings.xMin = [];
    settings.xMax = [];
end
if strcmp(settings.yScale, 'log') && ...
        ((~isempty(settings.yMin) && settings.yMin <= 0) || ...
        (~isempty(settings.yMax) && settings.yMax <= 0))
    settings.yMin = [];
    settings.yMax = [];
end
end

function value = loadYCompensation(preferenceGroup)
% 读取持久化 Y 轴补偿；缺失或损坏时恢复为 0 dB。
value = 0;
if ~ispref(preferenceGroup, 'YCompensation')
    return;
end
try
    savedValue = getpref(preferenceGroup, 'YCompensation');
    if isnumeric(savedValue) && isscalar(savedValue) && isfinite(savedValue)
        value = savedValue;
    end
catch
    value = 0;
end
end

function settings = loadStyleSettings(preferenceGroup)
% 读取持久化图形属性，并用默认值修复缺失或无效字段。
settings = struct( ...
    'titleText', 'PSR 测试数据', ...
    'xLabelText', 'Wavelength (nm)', ...
    'yLabelText', 'Loss (dB)', ...
    'axesFontSize', 15, ...
    'legendFontSize', 12, ...
    'legendColumns', 1, ...
    'legendLocation', 'best', ...
    'boldAxisLabels', true, ...
    'showLegend', true, ...
    'showGrid', true, ...
    'useDefaultLegend', true, ...
    'showYLimitLines', false, ...
    'lineWidth', 1.2, ...
    'renderer', 'opengl');

if ~ispref(preferenceGroup, 'StyleSettings')
    return;
end

try
    savedSettings = getpref(preferenceGroup, 'StyleSettings');
catch
    return;
end

settingNames = fieldnames(settings);
for settingIndex = 1:numel(settingNames)
    settingName = settingNames{settingIndex};
    if isstruct(savedSettings) && isfield(savedSettings, settingName)
        settings.(settingName) = savedSettings.(settingName);
    end
end

if ~(ischar(settings.titleText) || (isstring(settings.titleText) && isscalar(settings.titleText)))
    settings.titleText = 'PSR 测试数据';
end
if ~(ischar(settings.xLabelText) || (isstring(settings.xLabelText) && isscalar(settings.xLabelText)))
    settings.xLabelText = 'Wavelength (nm)';
end
if ~(ischar(settings.yLabelText) || (isstring(settings.yLabelText) && isscalar(settings.yLabelText)))
    settings.yLabelText = 'Loss (dB)';
end
settings.titleText = char(settings.titleText);
settings.xLabelText = char(settings.xLabelText);
settings.yLabelText = char(settings.yLabelText);

if ~(isnumeric(settings.axesFontSize) && isscalar(settings.axesFontSize) && ...
        isfinite(settings.axesFontSize) && settings.axesFontSize >= 1 && settings.axesFontSize <= 100)
    settings.axesFontSize = 15;
end
if ~(isnumeric(settings.legendFontSize) && isscalar(settings.legendFontSize) && ...
        isfinite(settings.legendFontSize) && settings.legendFontSize >= 1 && settings.legendFontSize <= 100)
    settings.legendFontSize = 12;
end
if ~(isnumeric(settings.legendColumns) && isscalar(settings.legendColumns) && ...
        isfinite(settings.legendColumns) && settings.legendColumns >= 1 && settings.legendColumns <= 20)
    settings.legendColumns = 1;
end
settings.legendColumns = round(settings.legendColumns);

validLocations = {'best', 'northeast', 'northwest', 'southeast', ...
    'southwest', 'north', 'south', 'east', 'west'};
if ~(ischar(settings.legendLocation) || ...
        (isstring(settings.legendLocation) && isscalar(settings.legendLocation))) || ...
        ~any(strcmp(char(settings.legendLocation), validLocations))
    settings.legendLocation = 'best';
else
    settings.legendLocation = char(settings.legendLocation);
end

logicalNames = {'boldAxisLabels', 'showLegend', 'showGrid', ...
    'useDefaultLegend', 'showYLimitLines'};
for logicalIndex = 1:numel(logicalNames)
    logicalName = logicalNames{logicalIndex};
    logicalValue = settings.(logicalName);
    if ~(islogical(logicalValue) && isscalar(logicalValue)) && ...
            ~(isnumeric(logicalValue) && isscalar(logicalValue) && any(logicalValue == [0 1]))
        settings.(logicalName) = true;
    else
        settings.(logicalName) = logical(logicalValue);
    end
end

if ~(isnumeric(settings.lineWidth) && isscalar(settings.lineWidth) && ...
        isfinite(settings.lineWidth) && settings.lineWidth >= 0.1 && settings.lineWidth <= 20)
    settings.lineWidth = 1.2;
end

validRenderers = {'opengl', 'painters'};
if ~(ischar(settings.renderer) || ...
        (isstring(settings.renderer) && isscalar(settings.renderer))) || ...
        ~any(strcmp(char(settings.renderer), validRenderers))
    settings.renderer = 'opengl';
else
    settings.renderer = char(settings.renderer);
end
end

function legendLabels = loadLegendLabels(preferenceGroup)
% 读取“完整文件路径 -> 图例名称”映射，并丢弃损坏条目。
legendLabels = struct('files', {{}}, 'labels', {{}});
if ~ispref(preferenceGroup, 'LegendLabels')
    return;
end

try
    savedLabels = getpref(preferenceGroup, 'LegendLabels');
catch
    return;
end

if ~isstruct(savedLabels) || ~isfield(savedLabels, 'files') || ...
        ~isfield(savedLabels, 'labels') || ~iscell(savedLabels.files) || ...
        ~iscell(savedLabels.labels) || numel(savedLabels.files) ~= numel(savedLabels.labels)
    return;
end

validEntries = cellfun(@(fileName, label) ...
    (ischar(fileName) || (isstring(fileName) && isscalar(fileName))) && ...
    (ischar(label) || (isstring(label) && isscalar(label))), ...
    savedLabels.files, savedLabels.labels);
legendLabels.files = cellfun(@char, savedLabels.files(validEntries), 'UniformOutput', false);
legendLabels.labels = cellfun(@char, savedLabels.labels(validEntries), 'UniformOutput', false);
end

function position = loadWindowPosition(preferenceGroup)
% 恢复上次窗口位置；尺寸过小时退回默认值以保证控件可用。
position = [80 80 1280 760];
if ~ispref(preferenceGroup, 'WindowPosition')
    return;
end

try
    savedPosition = getpref(preferenceGroup, 'WindowPosition');
catch
    return;
end

if isnumeric(savedPosition) && isequal(size(savedPosition), [1 4]) && ...
        all(isfinite(savedPosition)) && savedPosition(3) >= 1120 && savedPosition(4) >= 620
    position = savedPosition;
end
end
