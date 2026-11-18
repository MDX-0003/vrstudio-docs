; VRAIGC 离线安装器（决策 102）。
; 按当前用户安装到 %LOCALAPPDATA%\Programs\VRAIGC，数据目录在安装向导里选，
; 安装末尾把数据根与 vrgen/bin 的绝对路径写入 %APPDATA%\vrstudio\default.toml。
; 编译：build-installer.ps1 会传入 /DAppVersion /DStageDir /DOutputDir。

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef StageDir
  #define StageDir "..\build\app"
#endif
#ifndef OutputDir
  #define OutputDir "..\build"
#endif

[Setup]
AppId={{A3B7F2C9-6D1E-4B8A-9F0C-2E5D7A41C6B3}
AppName=VRAIGC
AppVersion={#AppVersion}
AppVerName=VRAIGC {#AppVersion}
VersionInfoVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\VRAIGC
DefaultGroupName=VRAIGC
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=VRAIGC-{#AppVersion}-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName=VRAIGC {#AppVersion}
ArchitecturesInstallIn64BitMode=x64compatible

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Dirs]
Name: "{app}\tools"

[Run]
Filename: "{app}\vrstudio.exe"; Description: "启动 VRAIGC"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
; 只清理安装目录；数据目录在 {app} 之外，卸载不碰它。
Type: filesandordirs; Name: "{app}\_internal"

[Code]
var
  DataPage: TInputDirWizardPage;
  DataRoot: String;

function EscapeToml(S: String): String;
begin
  // TOML 基本字符串里反斜杠是转义符，Windows 路径必须写成双反斜杠。
  S := StringChangeEx(S, '\', '\\', True);
  S := StringChangeEx(S, '"', '\"', True);
  Result := S;
end;

procedure InitializeWizard;
begin
  DataPage := CreateInputDirPage(wpSelectDir,
    '选择数据目录',
    'cases、sources、vrgen_runs、logs 会放在这个目录下。',
    '建议放在非系统盘的英文路径；如果是从旧机器迁移，直接指到迁移包解压出的目录。',
    False, '');
  DataPage.Add('数据目录：');
  if DirExists('D:\') then
    DataRoot := 'D:\VRAIGC-data'
  else
    DataRoot := ExpandConstant('{localappdata}\VRAIGC\data');
  DataPage.Values[0] := DataRoot;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = DataPage.ID then
  begin
    DataRoot := Trim(DataPage.Values[0]);
    if DataRoot = '' then
    begin
      MsgBox('请填写数据目录。', mbError, MB_OK);
      Result := False;
      Exit;
    end;
    if not ForceDirectories(DataRoot) then
    begin
      MsgBox('无法创建数据目录：' + DataRoot, mbError, MB_OK);
      Result := False;
    end;
  end;
end;

procedure WriteMachineConfig;
var
  ConfigPath, Text: String;
begin
  ConfigPath := ExpandConstant('{userappdata}\vrstudio\default.toml');
  ForceDirectories(ExtractFileDir(ConfigPath));
  Text :=
    '# 由 VRAIGC 安装器写入（决策 102）：数据根与两个可执行文件位置。' + #13#10 +
    '[paths]' + #13#10 +
    'data_root = "' + EscapeToml(DataRoot) + '"' + #13#10 +
    #13#10 +
    '[generate]' + #13#10 +
    'vrgen = "' + EscapeToml(ExpandConstant('{app}\vrgen\vrgen.exe')) + '"' + #13#10 +
    #13#10 +
    '[bin]' + #13#10 +
    'dir = "' + EscapeToml(ExpandConstant('{app}\bin')) + '"' + #13#10;
  if not SaveStringToFile(ConfigPath, Text, False) then
    MsgBox('写本机配置失败：' + ConfigPath + #13#10 +
           '可以手工创建该文件，内容见安装目录下的 README-install.txt。', mbError, MB_OK);
end;

procedure CheckMglc;
var
  Rc: Integer;
  Local: String;
begin
  Local := ExpandConstant('{localappdata}\Programs\mglc\bin\mglc.exe');
  if FileExists(Local) then
    Exit;
  if Exec('cmd.exe', '/c where mglc >nul 2>nul', '', SW_HIDE, ewWaitUntilTerminated, Rc) and (Rc = 0) then
    Exit;
  MsgBox('未检测到 mglc，生成功能暂时不可用。' + #13#10#13#10 +
         '1) 向管理员索取 mglc 的 Windows 版本；' + #13#10 +
         '2) 解压到 ' + ExpandConstant('{localappdata}') + '\Programs\mglc\bin；' + #13#10 +
         '3) 新开终端执行：mglc login --access-key <AK> --secret-key <SK>。' + #13#10#13#10 +
         '详见安装目录下的 README-install.txt。', mbInformation, MB_OK);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    WriteMachineConfig;
    CheckMglc;
  end;
end;
