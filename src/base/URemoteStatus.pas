{* Optional local playback status connection for a companion service. *}
unit URemoteStatus;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface

uses
  Classes, SysUtils;

type
  { All public methods are called by the game thread. Network I/O is confined
    to Execute; only the latest snapshot is retained when the peer is away. }
  TRemoteStatus = class(TThread)
  private
    FPort: Word;
    FLock: TRTLCriticalSection;
    FState, FArtist, FTitle, FSongFile: UTF8String;
    FRevision: QWord;
    function Snapshot(out Revision: QWord): UTF8String;
  protected
    procedure Execute; override;
  public
    constructor Create(APort: Word);
    destructor Destroy; override;
    procedure Started(const Artist, Title, SongFile: UTF8String);
    procedure Paused(IsPaused: Boolean);
    procedure Stopped;
  end;

var
  RemoteStatus: TRemoteStatus = nil;

implementation

uses
  fpjson, sockets, ssockets;

constructor TRemoteStatus.Create(APort: Word);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  InitCriticalSection(FLock);
  FPort := APort;
  FState := 'idle';
  FRevision := 1;
end;

destructor TRemoteStatus.Destroy;
begin
  Terminate;
  WaitFor;
  DoneCriticalSection(FLock);
  inherited;
end;

procedure TRemoteStatus.Started(const Artist, Title, SongFile: UTF8String);
begin
  EnterCriticalSection(FLock);
  try
    FState := 'playing';
    FArtist := Artist;
    FTitle := Title;
    FSongFile := SongFile;
    Inc(FRevision);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TRemoteStatus.Paused(IsPaused: Boolean);
var
  NewState: UTF8String;
begin
  if IsPaused then NewState := 'paused' else NewState := 'playing';
  EnterCriticalSection(FLock);
  try
    if (FState <> 'idle') and (FState <> NewState) then
    begin
      FState := NewState;
      Inc(FRevision);
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TRemoteStatus.Stopped;
begin
  EnterCriticalSection(FLock);
  try
    if FState <> 'idle' then
    begin
      FState := 'idle';
      FArtist := '';
      FTitle := '';
      FSongFile := '';
      Inc(FRevision);
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TRemoteStatus.Snapshot(out Revision: QWord): UTF8String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    EnterCriticalSection(FLock);
    try
      Obj.Add('type', 'status');
      Obj.Add('state', FState);
      Obj.Add('artist', FArtist);
      Obj.Add('title', FTitle);
      Obj.Add('song_file', FSongFile);
      Revision := FRevision;
    finally
      LeaveCriticalSection(FLock);
    end;
    Result := Obj.AsJSON + #10;
  finally
    Obj.Free;
  end;
end;

procedure TRemoteStatus.Execute;
var
  Connection: TInetSocket;
  Data: UTF8String;
  Revision, LastRevision, LastSent: QWord;
  Offset, Written: Integer;
  {$IFDEF DARWIN}
  NoSigPipe: LongInt;
  {$ENDIF}
begin
  Connection := nil;
  LastRevision := 0;
  LastSent := 0;
  try
    while not Terminated do
    begin
      if Connection = nil then
      begin
        try
          Connection := TInetSocket.Create('127.0.0.1', FPort, 250);
          Connection.IOTimeout := 250;
          {$IFDEF LINUX}
          // Linux MSG_NOSIGNAL: a disconnected peer must not terminate USDX.
          Connection.WriteFlags := $4000;
          {$ENDIF}
          {$IFDEF DARWIN}
          // macOS SO_NOSIGPIPE.
          NoSigPipe := 1;
          if fpSetSockOpt(Connection.Handle, SOL_SOCKET, $1022, @NoSigPipe, SizeOf(NoSigPipe)) <> 0 then
            raise Exception.Create('Unable to suppress SIGPIPE');
          {$ENDIF}
          LastRevision := 0;
        except
          FreeAndNil(Connection);
        end;
      end;

      if Connection <> nil then
      begin
        Data := Snapshot(Revision);
        if (Revision <> LastRevision) or (GetTickCount64 - LastSent >= 2000) then
        begin
          Offset := 1;
          try
            while (Offset <= Length(Data)) and not Terminated do
            begin
              Written := Connection.Write(Data[Offset], Length(Data) - Offset + 1);
              if Written <= 0 then
                raise Exception.Create('Status connection closed');
              Inc(Offset, Written);
            end;
            LastRevision := Revision;
            LastSent := GetTickCount64;
          except
            FreeAndNil(Connection);
          end;
        end;
      end;
      Sleep(200);
    end;
  finally
    Connection.Free;
  end;
end;

end.
