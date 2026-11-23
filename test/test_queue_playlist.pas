program test_queue_playlist;

{$mode delphi}
{$codepage utf8}

uses
  {$ifdef unix}cthreads,{$endif}
  Classes, SysUtils, UPath, UPathUtils, ULog, USong, USongs, UPlaylist;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
  begin
    WriteLn(StdErr, MessageText);
    Halt(1);
  end;
end;

var
  Lines: TStringList;
  Manager: TPlaylistManager;
  I: Integer;
begin
  Check(ParamCount = 1, 'Expected a temporary playlist directory');
  SetMultiByteConversionCodePage(CP_UTF8);
  PlaylistPath := Path(UTF8String(ParamStr(1))).GetAbsolutePath;
  CatSongs := TCatSongs.Create;
  SetLength(CatSongs.Song, 2);
  for I := 0 to 1 do
  begin
    CatSongs.Song[I] := TSong.Create;
    CatSongs.Song[I].Path := Path('/songs');
    CatSongs.Song[I].FileName := Path('song' + IntToStr(I) + '.txt');
    CatSongs.Song[I].Artist := 'Same artist';
    CatSongs.Song[I].Title := 'Same title';
  end;
  CatSongs.Song[1].FileName := Path('song-é.txt');

  Manager := TPlaylistManager.Create;
  Check(Length(Manager.Playlists) = 0, 'Expected no playlists at startup');
  Lines := TStringList.Create;
  try
    Lines.Add('#USDX_REQUESTS_QUEUE: 1');
    Lines.Add('#Name: queue');
    Lines.Add('#FixedOrder: On');
    Lines.Add('#USDX_FILE: /songs/song-é.txt');
    Lines.Add('Same artist : Same title');
    Lines.Add('#USDX_FILE: /songs/missing.txt');
    Lines.Add('Same artist : Same title');
    Lines.Add('Same artist : Same title');
    Lines.SaveToFile(PlaylistPath.Append('queue.upl').ToNative);
    Manager.DiscoverQueuePlaylist;
    Check(Length(Manager.Playlists) = 1, 'Queue was not discovered');
    Check(Manager.Playlists[0].FixedOrder, 'Queue order was not loaded');
    Check(Length(Manager.Playlists[0].Items) = 2, 'Missing path should not fall back to names');
    Check(Manager.Playlists[0].Items[0].SongID = 1, 'Exact path did not distinguish duplicate titles');
    Check(Manager.Playlists[0].Items[1].SongID = 0, 'Legacy name-only playlist entry did not load');
    Lines.Delete(3);
    Lines.Insert(3, '#USDX_FILE: /songs/song0.txt');
    Lines.SaveToFile(PlaylistPath.Append('queue.upl').ToNative);
    Check(Manager.ReloadPlayList(0, True), 'Forced reload failed');
    Check(Manager.Playlists[0].Items[0].SongID = 0, 'Forced reload did not read the new entry');
    WriteLn('Queue playlist loading passed');
  finally
    Lines.Free;
    Manager.Free;
    for I := 0 to High(CatSongs.Song) do CatSongs.Song[I].Free;
    CatSongs.Free;
  end;
end.
