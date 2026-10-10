#define AppName "Вкуснотека"
#ifndef AppVersion
  #define AppVersion "1.0.8"
#endif
#define AppExeName "recipe_vault.exe"

[Setup]
AppId={{3D7B8B39-348A-4A43-97D8-B0B27B9EF2B5}
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\RecipeVault
DefaultGroupName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=Vkusnoteka-Windows-Setup
SetupIconFile=..\app\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; Flags: unchecked

[Files]
Source: "..\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
Type: files; Name: "{userprograms}\Книга рецептов\Книга рецептов.lnk"
Type: files; Name: "{autodesktop}\Книга рецептов.lnk"

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Открыть Вкуснотеку"; Flags: nowait postinstall skipifsilent
