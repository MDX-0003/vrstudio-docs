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

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加图标："; Flags: unchecked

[Icons]
Name: "{group}\VRAIGC（本机）"; Filename: "{app}\vrstudio.exe"; WorkingDir: "{app}"
Name: "{group}\VRAIGC（局域网）"; Filename: "{app}\vrstudio.exe"; Parameters: "--lan"; WorkingDir: "{app}"
Name: "{group}\卸载 VRAIGC"; Filename: "{uninstallexe}"
Name: "{autodesktop}\VRAIGC"; Filename: "{app}\vrstudio.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\vrstudio.exe"; Description: "启动 VRAIGC"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
; 只清理安装目录；数据目录在 {app} 之外，卸载不碰它。
Type: filesandordirs; Name: "{app}\_internal"

[Code]
var
  DataPage: TInputDirWizardPage;
  DataRoot: String;

const
  CRLF = #13#10;

function UnescapeToml(S: String): String;
var
  I: Integer;
  R: String;
begin
  // 把配置里的 \\ 还原成单个 \。
  R := '';
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '\') and (I < Length(S)) and (S[I + 1] = '\') then
    begin
      R := R + '\';
      I := I + 2;
    end
    else
    begin
      R := R + S[I];
      I := I + 1;
    end;
  end;
  Result := R;
end;

procedure ShowInfo(const Text: String);
begin
  // 静默安装（/SILENT 或 /VERYSILENT）下不弹窗，否则会卡住无人值守安装。
  if not WizardSilent then
    MsgBox(Text, mbInformation, MB_OK);
end;

function EscapeToml(S: String): String;
var
  I: Integer;
  R: String;
begin
  // TOML 基本字符串里反斜杠是转义符，Windows 路径必须写成双反斜杠。
  R := '';
  for I := 1 to Length(S) do
  begin
    if S[I] = '\' then
      R := R + '\\'
    else if S[I] = '"' then
      R := R + '\"'
    else
      R := R + S[I];
  end;
  Result := R;
end;

function PreviousDataRoot(): String;
var
  Lines: TArrayOfString;
  I: Integer;
  Line: String;
  FirstQuote, LastQuote: Integer;
begin
  Result := '';
  if not FileExists(ExpandConstant('{userappdata}\vrstudio\default.toml')) then
    Exit;
  if not LoadStringsFromFile(ExpandConstant('{userappdata}\vrstudio\default.toml'), Lines) then
    Exit;
  for I := 0 to GetArrayLength(Lines) - 1 do
  begin
    Line := Trim(Lines[I]);
    if Pos('data_root', Line) = 1 then
    begin
      FirstQuote := Pos('"', Line);
      LastQuote := Length(Line);
      while (LastQuote > FirstQuote) and (Line[LastQuote] <> '"') do
        LastQuote := LastQuote - 1;
      if (FirstQuote > 0) and (LastQuote > FirstQuote) then
      begin
        Result := Copy(Line, FirstQuote + 1, LastQuote - FirstQuote - 1);
        // 配置文件里的路径是 TOML 转义写法（\\），读回来要还原成单反斜杠。
        Result := UnescapeToml(Result);
      end;
      Exit;
    end;
  end;
end;

procedure InitializeWizard;
var
  Previous: String;
begin
  DataPage := CreateInputDirPage(wpSelectDir,
    '选择数据目录',
    'cases、sources、vrgen_runs、logs 会放在这个目录下。',
    '建议放在非系统盘的英文路径；如果是从旧机器迁移，直接指到迁移包解压出的目录。',
    False, '');
  DataPage.Add('数据目录：');
  // 重复运行安装器（升级）时沿用已写好的数据目录，避免手滑把数据指到别处。
  Previous := PreviousDataRoot();
  if Previous <> '' then
    DataRoot := Previous
  else if DirExists('D:\') then
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
      Exit;
    end;
    // 数据放进程序目录会在升级或卸载时跟着被替换/删除，明确拦一下。
    if CompareText(Copy(DataRoot, 1, Length(ExpandConstant('{app}'))),
                   ExpandConstant('{app}')) = 0 then
    begin
      if MsgBox('数据目录在程序目录里面，升级或卸载可能影响数据。' + CRLF +
                '建议改成程序目录之外的路径（例如 D:\VRAIGC-data）。' + CRLF + CRLF +
                '仍然使用 ' + DataRoot + ' 吗？',
                mbConfirmation, MB_YESNO) = IDNO then
      begin
        Result := False;
        Exit;
      end;
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
    '# Written by the VRAIGC installer (decision 102): data root and binary paths.' + CRLF +
    '[paths]' + CRLF +
    'data_root = "' + EscapeToml(DataRoot) + '"' + CRLF +
    CRLF +
    '[generate]' + CRLF +
    'vrgen = "' + EscapeToml(ExpandConstant('{app}\vrgen\vrgen.exe')) + '"' + CRLF +
    CRLF +
    '[bin]' + CRLF +
    'dir = "' + EscapeToml(ExpandConstant('{app}\bin')) + '"' + CRLF;
  if not SaveStringToFile(ConfigPath, Text, False) then
    ShowInfo('写本机配置失败：' + ConfigPath + CRLF +
             '可以手工创建该文件，内容见安装目录下的 README-install.txt。');
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
  ShowInfo('未检测到 mglc，生成功能暂时不可用。' + CRLF + CRLF +
           '1) 向管理员索取 mglc 的 Windows 版本；' + CRLF +
           '2) 解压到 ' + ExpandConstant('{localappdata}') + '\Programs\mglc\bin；' + CRLF +
           '3) 新开终端执行：mglc login --access-key <AK> --secret-key <SK>。' + CRLF + CRLF +
           '详见安装目录下的 README-install.txt。');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    WriteMachineConfig;
    CheckMglc;
  end;
end;
