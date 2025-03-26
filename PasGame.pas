program PasGame;

{$mode objfpc}{$H+}

uses
  SDL2, SDL2_image, SDL2_ttf, SDL2_mixer, SysUtils, Classes, fpjson, jsonparser, fgl;

const
  SCREEN_WIDTH = 640;
  SCREEN_HEIGHT = 480;

  // Colors
  BLACK = $FF000000;
  WHITE = $FFFFFFFF;
  RED = $FFFF0000;
  GREEN = $FF00FF00;
  BLUE = $FF0000FF;
  YELLOW = $FFFFFF00;
  CYAN = $FF00FFFF;
  MAGENTA = $FFFF00FF;
  ORANGE = $FFFF8000;
  PURPLE = $FF800080;
  PINK = $FFFFC0CB;
  BROWN = $FFA52A2A;
  GRAY = $FF808080;
  LIME = $FF32CD32;
  TEAL = $FF008080;
  NAVY = $FF000080;

type
  TLayer = class
  private
    Name: string;              // Layer name, e.g., "Base", "Objects"
    Width: Integer;            // Layer width in tiles
    Height: Integer;           // Layer height in tiles
    Data: array of Integer;    // 1D array of tile indices
  end;

  TLayerList = specialize TFPGObjectList<TLayer>;

  TMap = class
  private
    Width: Integer;            // Map width in tiles
    Height: Integer;           // Map height in tiles
    TileWidth: Integer;        // Width of each tile in pixels
    TileHeight: Integer;       // Height of each tile in pixels
    Layers: TLayerList;     // List of layers
    TilesetTexture: PSDL_Texture; // Texture for the tileset image
    TilesetColumns: Integer;// Number of columns in the tileset
  public
    constructor Create;
    destructor Destroy; override;
    function GetTile(layerName: string; x, y: Integer): Integer; // Helper to get tile at (x,y)
  end;

  TPasGame = class
  private
    Window: PSDL_Window;
    Renderer: PSDL_Renderer;
    DefaultFont: PTTF_Font;
    FSound: PMix_Chunk;   // For sound effects
    FMusic: PMix_Music;   // For background music
    KeyStates: PUInt8;
    MouseState: UInt32;
    MouseX_: Integer;
    MouseY_: Integer;
    CamX, CamY: Integer;
    CamZoom: Double;
    CamActive: Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Run;

    // Core functions to be implemented by user
    procedure Init; virtual; abstract;
    procedure Update; virtual; abstract;
    procedure Draw; virtual; abstract;

    // API functions
    procedure cls(color: UInt32);
    procedure pset(x, y: Integer; color: UInt32);
    function pget(x, y: Integer): UInt32;
    procedure line(x1, y1, x2, y2: Integer; color: UInt32);
    procedure spr(path: string; x, y: Integer);
    procedure rect(x, y, w, h: Integer; color: UInt32);
    procedure rectb(x, y, w, h: Integer; color: UInt32);
    procedure circ(cx, cy, r: Integer; color: UInt32);
    procedure text(str: string; x, y: Integer; color: UInt32);
    function btn(key: Integer): Boolean;
    function mouseX: Integer;
    function mouseY: Integer;
    function mouseBtn(button: Integer = 1): Boolean;
    procedure cam(x, y: Integer);
    procedure cam_zoom(zoom: Double);
    procedure cam_on;
    procedure cam_off;
    procedure snd(path: string);          // Play a sound effect
    procedure music(path: string);        // Play looped background music
    procedure StopMusic;                  // Stop background music

    // Collision detection
    function collidesRect(x1, y1, w1, h1, x2, y2, w2, h2: Integer): Boolean;
    function collidesCircle(x1, y1, r1, x2, y2, r2: Integer): Boolean;
    function collidesPointRect(px, py, rx, ry, rw, rh: Integer): Boolean;
    function collidesPointCircle(px, py, cx, cy, r: Integer): Boolean;

    // Transform coordinates based on camera
    function transformX(x: Integer): Integer;
    function transformY(y: Integer): Integer;
    function transformSize(size: Integer): Integer;

    // Map procedures
    procedure LoadMap(filename: string; tilesetImagePath: string; map: TMap);
    procedure DrawMap(map: TMap);
  end;

  TGameApp = class(TPasGame)
  private
    FMap: TMap;
  public
    procedure Init; override;
    procedure Update; override;
    procedure Draw; override;
  end;

// TPasGame implementation

constructor TPasGame.Create;
begin
  if SDL_Init(SDL_INIT_VIDEO or SDL_INIT_TIMER) < 0 then
    raise Exception.Create('SDL could not initialize! SDL_Error: ' + SDL_GetError());

  if IMG_Init(IMG_INIT_PNG) = 0 then
    raise Exception.Create('SDL_image could not initialize! SDL_image Error: ' + IMG_GetError());

  if TTF_Init() = -1 then
    raise Exception.Create('SDL_ttf could not initialize! SDL_ttf Error: ' + TTF_GetError());

  Window := SDL_CreateWindow('PasGame', SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                            SCREEN_WIDTH, SCREEN_HEIGHT, SDL_WINDOW_SHOWN);
  if Window = nil then
    raise Exception.Create('Window could not be created! SDL_Error: ' + SDL_GetError());

  Renderer := SDL_CreateRenderer(Window, -1, SDL_RENDERER_ACCELERATED or SDL_RENDERER_PRESENTVSYNC);
  if Renderer = nil then
    raise Exception.Create('Renderer could not be created! SDL_Error: ' + SDL_GetError());
  // Initialize SDL2_mixer
  if Mix_OpenAudio(44100, MIX_DEFAULT_FORMAT, 2, 2048) < 0 then
    WriteLn('SDL_mixer could not initialize! Mix_Error: ', Mix_GetError());

  FSound := nil;
  FMusic := nil;

  // Load default font
  DefaultFont := TTF_OpenFont('font.ttf', 14);
  if DefaultFont = nil then
    WriteLn('Warning: Default font could not be loaded! TTF_Error: ' + TTF_GetError());

  CamX := 0;
  CamY := 0;
  CamZoom := 1.0;
  CamActive := True;
end;

destructor TPasGame.Destroy;
begin
  TTF_CloseFont(DefaultFont);
  SDL_DestroyRenderer(Renderer);
  SDL_DestroyWindow(Window);
  TTF_Quit();
  IMG_Quit();
  SDL_Quit();
  if FSound <> nil then
    Mix_FreeChunk(FSound);
  if FMusic <> nil then
    Mix_FreeMusic(FMusic);
  Mix_CloseAudio;
  inherited;
end;

function TPasGame.transformX(x: Integer): Integer;
begin
  if CamActive then
    Result := Round((x - CamX) * CamZoom)
  else
    Result := x;
end;

function TPasGame.transformY(y: Integer): Integer;
begin
  if CamActive then
    Result := Round((y - CamY) * CamZoom)
  else
    Result := y;
end;

function TPasGame.transformSize(size: Integer): Integer;
begin
  if CamActive then
    Result := Round(size * CamZoom)
  else
    Result := size;
end;

procedure TPasGame.Run;
var
  Event: TSDL_Event;
  Running: Boolean;
  LastTime, CurrentTime, DeltaTime: UInt32;
begin
  Running := True;
  LastTime := SDL_GetTicks();

  // Call user's init function
  Init;

  while Running do
  begin
    // Process events
    while SDL_PollEvent(@Event) = 1 do
    begin
      case Event.type_ of
        SDL_QUITEV: Running := False;
      end;
    end;

    // Update keyboard and mouse states
    KeyStates := SDL_GetKeyboardState(nil);
    MouseState := SDL_GetMouseState(@MouseX_, @MouseY_);

    // Call user's update function
    Update;

    // Call user's draw function
    Draw;

    // Present the renderer
    SDL_RenderPresent(Renderer);

    // Calculate delta time
    CurrentTime := SDL_GetTicks();
    DeltaTime := CurrentTime - LastTime;
    LastTime := CurrentTime;

    // Cap at 60 FPS
    if DeltaTime < 16 then
      SDL_Delay(16 - DeltaTime);
  end;
end;

procedure TPasGame.cls(color: UInt32);
var
  r, g, b, a: Byte;
begin
  r := (color shr 16) and $FF;
  g := (color shr 8) and $FF;
  b := color and $FF;
  a := (color shr 24) and $FF;

  SDL_SetRenderDrawColor(Renderer, r, g, b, a);
  SDL_RenderClear(Renderer);
end;

procedure TPasGame.pset(x, y: Integer; color: UInt32);
var
  r, g, b, a: Byte;
  tx, ty: Integer;
begin
  r := (color shr 16) and $FF;
  g := (color shr 8) and $FF;
  b := color and $FF;
  a := (color shr 24) and $FF;

  tx := transformX(x);
  ty := transformY(y);

  SDL_SetRenderDrawColor(Renderer, r, g, b, a);
  SDL_RenderDrawPoint(Renderer, tx, ty);
end;

function TPasGame.pget(x, y: Integer): UInt32;
var
  pixel: TSDL_Color;
  surface: PSDL_Surface;
  tx, ty: Integer;
begin
  tx := transformX(x);
  ty := transformY(y);

  // Create a temporary surface to read the pixel
  surface := SDL_CreateRGBSurface(0, SCREEN_WIDTH, SCREEN_HEIGHT, 32, 0, 0, 0, 0);
  SDL_RenderReadPixels(Renderer, nil, SDL_PIXELFORMAT_RGBA8888, surface^.pixels, surface^.pitch);

  // Get the pixel color
  SDL_GetRGBA(PUInt32(UIntPtr(surface^.pixels) + ty * surface^.pitch + tx * 4)^, surface^.format, @pixel.r, @pixel.g, @pixel.b, @pixel.a);

  SDL_FreeSurface(surface);

  // Return the color as UInt32
  Result := (pixel.a shl 24) or (pixel.r shl 16) or (pixel.g shl 8) or pixel.b;
end;

procedure TPasGame.line(x1, y1, x2, y2: Integer; color: UInt32);
var
  r, g, b, a: Byte;
  tx1, ty1, tx2, ty2: Integer;
begin
  r := (color shr 16) and $FF;
  g := (color shr 8) and $FF;
  b := color and $FF;
  a := (color shr 24) and $FF;

  tx1 := transformX(x1);
  ty1 := transformY(y1);
  tx2 := transformX(x2);
  ty2 := transformY(y2);

  SDL_SetRenderDrawColor(Renderer, r, g, b, a);
  SDL_RenderDrawLine(Renderer, tx1, ty1, tx2, ty2);
end;

procedure TPasGame.spr(path: string; x, y: Integer);
var
  surface: PSDL_Surface;
  texture: PSDL_Texture;
  srcRect, dstRect: TSDL_Rect;
  tx, ty: Integer;
begin
  surface := IMG_Load(PChar(path));
  if surface = nil then
  begin
    WriteLn('Unable to load image! SDL_image Error: ' + IMG_GetError());
    Exit;
  end;

  texture := SDL_CreateTextureFromSurface(Renderer, surface);
  if texture = nil then
  begin
    WriteLn('Unable to create texture! SDL Error: ' + SDL_GetError());
    SDL_FreeSurface(surface);
    Exit;
  end;

  tx := transformX(x);
  ty := transformY(y);

  srcRect.x := 0;
  srcRect.y := 0;
  srcRect.w := surface^.w;
  srcRect.h := surface^.h;

  dstRect.x := tx;
  dstRect.y := ty;
  dstRect.w := transformSize(surface^.w);
  dstRect.h := transformSize(surface^.h);

  SDL_RenderCopy(Renderer, texture, @srcRect, @dstRect);

  SDL_DestroyTexture(texture);
  SDL_FreeSurface(surface);
end;

procedure TPasGame.rect(x, y, w, h: Integer; color: UInt32);
var
  r, g, b, a: Byte;
  rectToDraw: TSDL_Rect;
  tx, ty, tw, th: Integer;
begin
  r := (color shr 16) and $FF;
  g := (color shr 8) and $FF;
  b := color and $FF;
  a := (color shr 24) and $FF;

  tx := transformX(x);
  ty := transformY(y);
  tw := transformSize(w);
  th := transformSize(h);

  rectToDraw.x := tx;
  rectToDraw.y := ty;
  rectToDraw.w := tw;
  rectToDraw.h := th;

  SDL_SetRenderDrawColor(Renderer, r, g, b, a);
  SDL_RenderFillRect(Renderer, @rectToDraw);
end;

procedure TPasGame.rectb(x, y, w, h: Integer; color: UInt32);
var
  r, g, b, a: Byte;
  rectToDraw: TSDL_Rect;
  tx, ty, tw, th: Integer;
begin
  r := (color shr 16) and $FF;
  g := (color shr 8) and $FF;
  b := color and $FF;
  a := (color shr 24) and $FF;

  tx := transformX(x);
  ty := transformY(y);
  tw := transformSize(w);
  th := transformSize(h);

  rectToDraw.x := tx;
  rectToDraw.y := ty;
  rectToDraw.w := tw;
  rectToDraw.h := th;

  SDL_SetRenderDrawColor(Renderer, r, g, b, a);
  SDL_RenderDrawRect(Renderer, @rectToDraw);
end;

procedure TPasGame.circ(cx, cy, r: Integer; color: UInt32);
var
  red, green, blue, alpha: Byte;
  tcx, tcy, tr: Integer;
  i: Integer;
  dx, dy: Integer;
begin
  red := (color shr 16) and $FF;
  green := (color shr 8) and $FF;
  blue := color and $FF;
  alpha := (color shr 24) and $FF;

  tcx := transformX(cx);
  tcy := transformY(cy);
  tr := transformSize(r);

  SDL_SetRenderDrawColor(Renderer, red, green, blue, alpha);

  // Draw circle using midpoint circle algorithm
  dx := tr;
  dy := 0;

  while dx >= dy do
  begin
    // Draw the eight octants
    SDL_RenderDrawPoint(Renderer, tcx + dx, tcy + dy);
    SDL_RenderDrawPoint(Renderer, tcx + dy, tcy + dx);
    SDL_RenderDrawPoint(Renderer, tcx - dy, tcy + dx);
    SDL_RenderDrawPoint(Renderer, tcx - dx, tcy + dy);
    SDL_RenderDrawPoint(Renderer, tcx - dx, tcy - dy);
    SDL_RenderDrawPoint(Renderer, tcx - dy, tcy - dx);
    SDL_RenderDrawPoint(Renderer, tcx + dy, tcy - dx);
    SDL_RenderDrawPoint(Renderer, tcx + dx, tcy - dy);

    // Fill the circle
    for i := -dx to dx do
    begin
      SDL_RenderDrawPoint(Renderer, tcx + i, tcy + dy);
      SDL_RenderDrawPoint(Renderer, tcx + i, tcy - dy);
    end;

for i := -dy to dy do
    begin
      SDL_RenderDrawPoint(Renderer, tcx + i, tcy + dx);
      SDL_RenderDrawPoint(Renderer, tcx + i, tcy - dx);
    end;

    Inc(dy);

    if (2 * dy + 1) > (2 * dx - 1) then
      Dec(dx);
  end;
end;

procedure TPasGame.text(str: string; x, y: Integer; color: UInt32);
var
  surface: PSDL_Surface;
  texture: PSDL_Texture;
  srcRect, dstRect: TSDL_Rect;
  textColor: TSDL_Color;
  tx, ty: Integer;
begin
  if DefaultFont = nil then
    Exit;

  textColor.r := (color shr 16) and $FF;
  textColor.g := (color shr 8) and $FF;
  textColor.b := color and $FF;
  textColor.a := (color shr 24) and $FF;

  surface := TTF_RenderText_Blended(DefaultFont, PChar(str), textColor);
  if surface = nil then
  begin
    WriteLn('Unable to render text! SDL_ttf Error: ' + TTF_GetError());
    Exit;
  end;

  texture := SDL_CreateTextureFromSurface(Renderer, surface);
  if texture = nil then
  begin
    WriteLn('Unable to create texture from rendered text! SDL Error: ' + SDL_GetError());
    SDL_FreeSurface(surface);
    Exit;
  end;

  tx := transformX(x);
  ty := transformY(y);

  srcRect.x := 0;
  srcRect.y := 0;
  srcRect.w := surface^.w;
  srcRect.h := surface^.h;

  dstRect.x := tx;
  dstRect.y := ty;
  dstRect.w := transformSize(surface^.w);
  dstRect.h := transformSize(surface^.h);

  SDL_RenderCopy(Renderer, texture, @srcRect, @dstRect);

  SDL_DestroyTexture(texture);
  SDL_FreeSurface(surface);
end;

function TPasGame.btn(key: Integer): Boolean;
begin
  Result := KeyStates[key] = 1;
end;

function TPasGame.mouseX: Integer;
begin
  Result := MouseX_;
end;

function TPasGame.mouseY: Integer;
begin
  Result := MouseY_;
end;

function TPasGame.mouseBtn(button: Integer = 1): Boolean;
begin
  case button of
    1: Result := (MouseState and SDL_BUTTON(SDL_BUTTON_LEFT)) <> 0;
    2: Result := (MouseState and SDL_BUTTON(SDL_BUTTON_MIDDLE)) <> 0;
    3: Result := (MouseState and SDL_BUTTON(SDL_BUTTON_RIGHT)) <> 0;
    else
      Result := False;
  end;
end;

procedure TPasGame.cam(x, y: Integer);
begin
  CamX := x;
  CamY := y;
end;

procedure TPasGame.cam_zoom(zoom: Double);
begin
  CamZoom := zoom;
end;

procedure TPasGame.cam_on;
begin
  CamActive := True;
end;

procedure TPasGame.cam_off;
begin
  CamActive := False;
end;

function TPasGame.collidesRect(x1, y1, w1, h1, x2, y2, w2, h2: Integer): Boolean;
begin
  Result := (x1 < x2 + w2) and
            (x1 + w1 > x2) and
            (y1 < y2 + h2) and
            (y1 + h1 > y2);
end;

function TPasGame.collidesCircle(x1, y1, r1, x2, y2, r2: Integer): Boolean;
var
  dx, dy: Integer;
  distance: Double;
begin
  dx := x2 - x1;
  dy := y2 - y1;
  distance := Sqrt(dx * dx + dy * dy);
  Result := distance < (r1 + r2);
end;

function TPasGame.collidesPointRect(px, py, rx, ry, rw, rh: Integer): Boolean;
begin
  Result := (px >= rx) and
            (px <= rx + rw) and
            (py >= ry) and
            (py <= ry + rh);
end;

function TPasGame.collidesPointCircle(px, py, cx, cy, r: Integer): Boolean;
var
  dx, dy: Integer;
  distance: Double;
begin
  dx := px - cx;
  dy := py - cy;
  distance := Sqrt(dx * dx + dy * dy);
  Result := distance <= r;
end;

procedure TPasGame.snd(path: string);
begin
  if FSound <> nil then
    Mix_FreeChunk(FSound);

  FSound := Mix_LoadWAV(PChar(path));
  if FSound = nil then
    WriteLn('Failed to load sound: ', Mix_GetError())
  else
    Mix_PlayChannel(-1, FSound, 0);  // Play once (no loop)
end;

procedure TPasGame.music(path: string);
begin
  if FMusic <> nil then
    Mix_FreeMusic(FMusic);

  FMusic := Mix_LoadMUS(PChar(path));
  if FMusic = nil then
    WriteLn('Failed to load music: ', Mix_GetError())
  else
    Mix_PlayMusic(FMusic, -1);  // Loop indefinitely (-1)
end;

procedure TPasGame.StopMusic;
begin
  if Mix_PlayingMusic() = 1 then
    Mix_HaltMusic;
end;

//TMap implementation
constructor TMap.Create;
begin
     inherited Create;
     Layers := TLayerList.Create(True);
end;

destructor TMap.Destroy;
var
  layer: TLayer;
begin
  for layer in Layers do
    layer.Free;              // Free each layer object
  Layers.Free;               // Free the layer list
  if TilesetTexture <> nil then
    SDL_DestroyTexture(TilesetTexture); // Clean up the tileset texture
  inherited;
end;

function TMap.GetTile(layerName: string; x, y: Integer): Integer;
var
  layer: TLayer;
begin
  for layer in Layers do
  begin
    if layer.Name = layerName then
    begin
      if (x >= 0) and (x < layer.Width) and (y >= 0) and (y < layer.Height) then
        Exit(layer.Data[y * layer.Width + x]) // Convert 2D coordinates to 1D index
      else
        Exit(0); // Out of bounds
    end;
  end;
  Exit(0); // Layer not found
end;

procedure TPasGame.LoadMap(filename: string; tilesetImagePath: string; map: TMap);
    var
      jsonStr: string;
      jsonData: TJSONData;
      jsonObj: TJSONObject;
      layersArray: TJSONArray;
      layerObj: TJSONObject;
      layer: TLayer;
      dataArray: TJSONArray;
      surface: PSDL_Surface;
      tilesetWidth: Integer;
      i, j: Integer;
    begin
      // Load JSON file into a string
      jsonStr := '';
      with TStringList.Create do
      try
        LoadFromFile(filename);
        jsonStr := Text;
      finally
        Free;
      end;

      // Parse JSON
      jsonData := GetJSON(jsonStr);
      try
        jsonObj := TJSONObject(jsonData);

        // Populate map properties from JSON
        map.Width := jsonObj.Get('width', 0);
        map.Height := jsonObj.Get('height', 0);
        map.TileWidth := jsonObj.Get('tilewidth', 0);
        map.TileHeight := jsonObj.Get('tileheight', 0);

        // Load tileset image from the separate file
        surface := IMG_Load(PChar(tilesetImagePath));
        if surface <> nil then
        begin
          // Create texture from surface
          map.TilesetTexture := SDL_CreateTextureFromSurface(Renderer, surface);
          // Get tileset image width
          tilesetWidth := surface^.w;
          SDL_FreeSurface(surface);
          // Calculate number of columns based on image width and tile width
          if map.TileWidth > 0 then
            map.TilesetColumns := tilesetWidth div map.TileWidth
          else
          begin
            map.TilesetColumns := 0;
            WriteLn('Error: TileWidth is zero, cannot calculate TilesetColumns');
          end;
        end
        else
        begin
          WriteLn('Failed to load tileset image: ' + IMG_GetError());
          map.TilesetTexture := nil;
          map.TilesetColumns := 0;
        end;

        // Load layers from JSON
        layersArray := jsonObj.Get('layers', TJSONArray.Create);
        for i := 0 to layersArray.Count - 1 do
        begin
          layerObj := TJSONObject(layersArray[i]);
          layer := TLayer.Create;
          layer.Name := layerObj.Get('name', '');
          layer.Width := layerObj.Get('width', 0);
          layer.Height := layerObj.Get('height', 0);
          SetLength(layer.Data, layer.Width * layer.Height);
          dataArray := layerObj.Get('data', TJSONArray.Create);
          for j := 0 to layer.Width * layer.Height - 1 do
            layer.Data[j] := dataArray[j].AsInteger;
          map.Layers.Add(layer);
        end;
      finally
        jsonData.Free;
      end;
end;

procedure TPasGame.DrawMap(map: TMap);
    var
      layer: TLayer;
      x, y, index: Integer;
      tileX, tileY: Integer;
      srcRect, dstRect: TSDL_Rect;
    begin
      if map.TilesetTexture = nil then Exit;

      for layer in map.Layers do
      begin
        for y := 0 to layer.Height - 1 do
        begin
          for x := 0 to layer.Width - 1 do
          begin
            index := layer.Data[y * layer.Width + x];
            if index > 0 then // 0 typically means no tile
            begin
              // Calculate source rectangle in tileset (index - 1 because Map Editor starts at 1)
              tileX := ((index - 1) mod map.TilesetColumns) * map.TileWidth;
              tileY := ((index - 1) div map.TilesetColumns) * map.TileHeight;
              srcRect.x := tileX;
              srcRect.y := tileY;
              srcRect.w := map.TileWidth;
              srcRect.h := map.TileHeight;

              // Calculate destination rectangle with camera transformation
              dstRect.x := transformX(x * map.TileWidth);
              dstRect.y := transformY(y * map.TileHeight);
              dstRect.w := transformSize(map.TileWidth);
              dstRect.h := transformSize(map.TileHeight);

              SDL_RenderCopy(Renderer, map.TilesetTexture, @srcRect, @dstRect);
            end;
          end;
        end;
      end;
end;

// TGameApp implementation - Example game

procedure TGameApp.Init;
begin
  // Initialize your game here
  //FMap := TMap.Create;
  //LoadMap('test1.json', 'test1.png',FMap);
  WriteLn('Game initialized!');
end;

procedure TGameApp.Update;
begin
  // Update game logic here

  // Example: Exit on Escape key press
  if btn(SDL_SCANCODE_ESCAPE) then
    SDL_Quit;
end;

procedure TGameApp.Draw;
begin
  // Clear the screen
  cls(BLACK);

  //DrawMap(FMap);
  // Draw game elements
  text('PasGame Example', 10, 10, GREEN);

  rect(100, 100, 50, 50, RED);
  circ(200, 150, 30, BLUE);
  line(300, 100, 350, 200, GREEN);

  // Draw mouse position
  text('Mouse: ' + IntToStr(mouseX) + ', ' + IntToStr(mouseY), 10, 30, YELLOW);

  // Draw a circle at mouse position if clicked
  if mouseBtn(1) then
    circ(mouseX, mouseY, 10, CYAN);
end;

// Main program
var
  Game: TGameApp;
begin
  Game := TGameApp.Create;
  try
    Game.Run;
  finally
    Game.Free;
  end;
end.
