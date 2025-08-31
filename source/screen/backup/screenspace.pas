unit ScreenSpace;

{$mode ObjFPC}{$H+}
{.$define DEBUG}


interface

uses
  RayLib, RayMath, Classes, SysUtils, ScreenManager, SpaceEngine, DigestMath, r3d, Math;

{ TSpaceShip }
type
  TSpaceShip = class(TSpaceActor)
  private
    FEnergy: Integer;
    FNumMatEngine: Integer;
    FShotColor: TColorB;

    FLastFireTime: Single;
    FFireRate: Single;
    FHitEffectTimer: Single;
    FHitEffectDuration: Single;
    FIsHit: Boolean;
    FHitPosition: TVector3;
    FHitNormal: TVector3;

    // R3D система частиц для эффектов попадания
    FHitParticleSystem: TR3D_ParticleSystem;
    FHitParticleMesh: TR3D_Mesh;
    FHitParticleMaterial: TR3D_Material;
    FHitScaleCurve: TR3D_InterpolationCurve;

    FIsDying: Boolean;           // Флаг процесса уничтожения
    FDeathTimer: Single;         // Таймер смерти
    FDeathDuration: Single;      // Продолжительность эффекта смерти

  public

    constructor Create(const AParent: TSpaceEngine); override;
    destructor Destroy; override;
    procedure Update(const DeltaTime: Single); override;
    procedure Shot; override;
    procedure OnCollision(const Actor: TSpaceActor); override;
    procedure Render; override;
    procedure ApplyHit(HitPos, HitNorm: TVector3; Damage: Single);
    procedure EmitHitParticles(HitPos, HitNorm: TVector3);

    procedure StartDeathSequence;
    procedure UpdateDeathEffects(DeltaTime: Single);

    property ShotColor: TColorB read FShotColor write FShotColor;
    property NumMatEngine: Integer read FNumMatEngine write FNumMatEngine;

    property Energy: Integer read FEnergy write FEnergy;
  end;


  { TAiShip }

  TAiShip = class(TSpaceShip)
  private

    FOrbitRadius: Single;
    FOrbitHeight: Single;
    FOrbitSpeed: Single;
    FOrbitAngleChangeTimer: Single;
    FTargetOrbitHeight: Single;
    FOrbitChangeTimer: Single;
    FTargetOrbitRadius: Single;

    FFireRange: Single;
    function CalculateRollInput(CurrentUp, TargetUp: TVector3): Single;
    function CalculatePitchInput(CurrentForward, TargetDirection: TVector3): Single;
    function CalculateYawInput(CurrentForward, TargetDirection: TVector3): Single;
  public
    constructor Create(const AParent: TSpaceEngine); override;
    procedure Update(const DeltaTime: Single); override;

  end;

  { TProjectile }



  { TSpaceGate }
  TSpaceGate = class(TSpaceActor)
  private
    Ring: TSpaceActor;
    BodyModel, RingModel: TR3D_Model;
  public
    constructor Create(const AParent: TSpaceEngine); override;
    procedure Update(const DeltaTime: Single); override;
  end;


  { TScreenSpace }

  TScreenSpace = class(TGameScreen)
  private
    Engine: TSpaceEngine;
    ShipModel:  array[0..5] of TR3D_Model;
    Ship: TSpaceShip;
    AiShip: array[0..5] of TAiShip;
    Gate: TSpaceGate;
    Camera: TSpaceCamera;

  public
    procedure Init; override; // Init game screen
    procedure Shutdown; override; // Shutdown the game screen
    procedure Update(MoveCount: Single); override; // Update the game screen
    procedure Render; override;  // Render the game screen
    procedure Show; override;  // Celled when the screen is showned
    procedure Hide; override; // Celled when the screen is hidden
  end;




implementation

constructor TSpaceShip.Create(const AParent: TSpaceEngine);
begin
  inherited Create(AParent);
  R3D_SetModelImportScale(0.1);


  ColliderType:= ctBox;
  ActorModel := Default(TR3D_Model);
  DoCollision := True;
  AlignToHorizon:=False;
  MaxSpeed:=20;

  // Настройки стрельбы
  FFireRate := 5.0;
  FLastFireTime := 0;

  // Настройки эффекта попадания
  FHitEffectDuration := 1.5;
  FHitEffectTimer := 0;
  FIsHit := False;

  // Создаем R3D меш для частиц
  FHitParticleMesh := R3D_GenMeshSphere(0.05, 8, 16, True);

  // Создаем материал для частиц
  FHitParticleMaterial := R3D_GetDefaultMaterial();
  FHitParticleMaterial.emission.color := ColorCreate(255, 100, 0, 255);
  FHitParticleMaterial.emission.energy := 200.0;
  FHitParticleMaterial.albedo.color := BLACK;

  // Создаем кривую для масштабирования частиц
  FHitScaleCurve := R3D_LoadInterpolationCurve(3);
  R3D_AddKeyframe(@FHitScaleCurve, 0.0, 0.0);
  R3D_AddKeyframe(@FHitScaleCurve, 0.5, 1.0);
  R3D_AddKeyframe(@FHitScaleCurve, 1.0, 0.0);

  // Создаем систему частиц
  FHitParticleSystem := R3D_LoadParticleSystem(512);

  // Настраиваем систему частиц
  FHitParticleSystem.initialColor := Green;
  FHitParticleSystem.colorVariance := BLUE;
  FHitParticleSystem.initialScale := Vector3Create(0.1, 0.1, 0.1);
  FHitParticleSystem.scaleVariance := 0.05;
  FHitParticleSystem.lifetime := 1.5;

  FHitParticleSystem.lifetimeVariance := 0.5;
  FHitParticleSystem.gravity := Vector3Create(0, -3.0, 0);
  FHitParticleSystem.spreadAngle := 45.0;
  FHitParticleSystem.scaleOverLifetime := @FHitScaleCurve;

  // Ручное управление эмиссией
  FHitParticleSystem.autoEmission := False;
  FHitParticleSystem.emissionRate := 512;

  R3D_CalculateParticleSystemBoundingBox(@FHitParticleSystem);
  TrailColor := BLUE;
  ShotColor := BLUE;

  FEnergy := 100;

  // Инициализация эффекта смерти
  FIsDying := False;
  FDeathTimer := 0;
  FDeathDuration := 2.0; // 2 секунды на эффект смерти

end;

destructor TSpaceShip.Destroy;
begin
  // Очищаем R3D ресурсы
  R3D_UnloadParticleSystem(@FHitParticleSystem);
  R3D_UnloadInterpolationCurve(FHitScaleCurve);
  R3D_UnloadMesh(@FHitParticleMesh);
  R3D_UnloadMaterial(@FHitParticleMaterial);

  inherited Destroy;
end;

procedure TSpaceShip.Update(const DeltaTime: Single);
begin
  if FIsDying then
  begin
    UpdateDeathEffects(DeltaTime);
    // Не вызываем inherited Update, чтобы корабль не двигался во время смерти
    Exit;
  end;

  inherited Update(DeltaTime);

  // Обновляем таймер эффекта попадания
  if FIsHit then
  begin
    FHitEffectTimer := FHitEffectTimer - DeltaTime;
    if FHitEffectTimer <= 0 then
    begin
      FIsHit := False;
      FHitEffectTimer := 0;
    end;
  end;

  // Обновляем систему частиц
  R3D_UpdateParticleSystem(@FHitParticleSystem, DeltaTime);
  if ActorModel.materialCount > 0 then
  begin

  // Визуальные эффекты двигателя с учетом попадания
  if FIsHit then
  begin
    // Мигающий эффект при попадании
    if Trunc(FHitEffectTimer * 8) mod 2 = 0 then
    begin
      ActorModel.materials[FNumMatEngine].emission.color := ColorCreate(255, 50, 0, 255);
      ActorModel.materials[FNumMatEngine].emission.energy := 400.0;
    end
    else
    begin
      ActorModel.materials[FNumMatEngine].emission.color := TrailColor;
      ActorModel.materials[FNumMatEngine].emission.energy := Clamp(Abs(Self.CurrentSpeed)/MaxSpeed * 300.0, 30.0, 300.0);
    end;
  end
  else
  begin
    ActorModel.materials[FNumMatEngine].emission.color := TrailColor;
    ActorModel.materials[FNumMatEngine].emission.energy := Clamp(Abs(Self.CurrentSpeed)/MaxSpeed * 300.0, 30.0, 300.0);
  end;
  ActorModel.materials[FNumMatEngine].albedo.color := BLACK;

  end;
end;

procedure TSpaceShip.Shot;
var
  CurrentTime: Single;
  StartPos: TVector3;
begin
  CurrentTime := GetTime();

  if (CurrentTime - FLastFireTime) < (0.5 / FFireRate) then
    Exit;

  FLastFireTime := CurrentTime;

  StartPos := Vector3Add(Position, Vector3Scale(GetForward(), 0.1));
  TImpulseLazer.Create(Engine, StartPos, GetForward(), 100.0, 25.0, ShotColor);
end;

procedure TSpaceShip.OnCollision(const Actor: TSpaceActor);
var
  HitPos, HitNorm: TVector3;
  Damage: Single;
  LazerColor: TColorB;
begin
  inherited OnCollision(Actor);

  // Проверяем, что это снаряд врага
  if (Actor is TImpulseLazer) then
  begin
    // Получаем цвет лазера
    LazerColor := TImpulseLazer(Actor).TrailColor;

    // Вычисляем точку попадания
    HitPos := Vector3Lerp(Position, Actor.Position, 0.3);
    HitNorm := Vector3Normalize(Vector3Subtract(Position, Actor.Position));

    // Наносим урон
    Damage := Actor.Tag;
    Energy := Energy - Trunc(Damage);
   // If Energy <= 0 then FIsDying := True;
      // Проверяем условие смерти
    if (FEnergy <= 0) and not IsDead then
    begin
       StartDeathSequence;
    end;

    LazerColor :=  TImpulseLazer(Actor).TrailColor;
    //FHitParticleSystem.initialColor := TImpulseLazer(Actor).TrailColor;
    //FHitParticleSystem.colorVariance :=TImpulseLazer(Actor).TrailColor;

    // Устанавливаем цвет частиц в соответствии с цветом лазера
    FHitParticleSystem.initialColor := LazerColor;

    FHitParticleMaterial.emission.color := LazerColor;

    FHitParticleSystem.colorVariance := ColorCreate(
      Byte(Round(Clamp(LazerColor.r + 30, 0, 255))),
      Byte(Round(Clamp(LazerColor.g + 30, 0, 255))),
      Byte(Round(Clamp(LazerColor.b + 30, 0, 255))),
      Byte(Round(Clamp(LazerColor.a + 30, 0, 255)))
    );

    ApplyHit(HitPos, HitNorm, Damage);
   // Уничтожаем снаряд
    Actor.Dead;
  end;
end;

procedure TSpaceShip.ApplyHit(HitPos, HitNorm: TVector3; Damage: Single);
begin
  FIsHit := True;
  FHitEffectTimer := FHitEffectDuration;
  FHitPosition := HitPos;
  FHitNormal := HitNorm;

  FHitParticleSystem.position := HitPos;
  R3D_CalculateParticleSystemBoundingBox(@FHitParticleSystem);

  // Эмитируем частицы эффекта
  EmitHitParticles(HitPos, HitNorm);

  // Эффект отдачи
  Velocity := Vector3Add(Velocity, Vector3Scale(HitNorm, Damage * 0.3));

  // Визуальная тряска
  RotateLocalEuler(Vector3Create(Random * 6 - 2, Random * 6 - 2, Random * 6 - 2), 1);
end;

procedure TSpaceShip.EmitHitParticles(HitPos, HitNorm: TVector3);
var
  i: Integer;
  baseVelocity: TVector3;
begin

  // Устанавливаем позицию системы частиц
  FHitParticleSystem.position := HitPos;

  // Базовое направление скорости
  baseVelocity := Vector3Scale(HitNorm, 3.0);
  FHitParticleSystem.initialVelocity := baseVelocity;
  FHitParticleSystem.velocityVariance := Vector3Create(1.5, 1.5, 1.5);

  // Эмитируем частицы вручную
  for i := 0 to 14*4 do
  begin
    R3D_EmitParticle(@FHitParticleSystem);
  end;
end;

procedure TSpaceShip.StartDeathSequence;
begin
  if FIsDying or IsDead then Exit;

  FIsDying := True;
  FDeathTimer := FDeathDuration;


  // Начальные значения для эффекта
  if ActorModel.materialCount > 0 then
  begin
    ActorModel.materials[0].emission.energy := 300.0; // Яркое свечение в начале
    ActorModel.materials[0].emission.color := RED;    // Красное свечение смерти
  end;

  // НЕ вызываем inherited Dead здесь - только после завершения анимации
  // inherited Dead;
end;

procedure TSpaceShip.UpdateDeathEffects(DeltaTime: Single);
var
  fadeFactor: Single;
begin
  if not FIsDying then Exit;

  FDeathTimer := FDeathTimer - DeltaTime;

  // Вычисляем коэффициент затухания (от 1.0 до 0.0)
  fadeFactor := FDeathTimer / FDeathDuration;

  // Плавно уменьшаем свечение материала
  if ActorModel.materialCount > 0 then
  begin
    ActorModel.materials[0].emission.energy := 300.0 * fadeFactor;

    // Меняем цвет от красного к оранжевому при затухании
    if fadeFactor > 0.5 then
      ActorModel.materials[0].emission.color := RED
    else
      ActorModel.materials[0].emission.color := ColorCreate(255, 100, 0, 255);
  end;

  // Также уменьшаем масштаб для эффекта исчезновения
  Scale := Scale * (0.99 - (DeltaTime * 0.5));

  // Добавляем случайное вращение при смерти
  RotateLocalEuler(Vector3Create(
    Random * 10 - 5,
    Random * 10 - 5,
    Random * 10 - 5
  ), DeltaTime * 90);

  // Завершаем эффект смерти
  if FDeathTimer <= 0 then
  begin
    FIsDying := False;
    // Полностью скрываем объект
    Visible := False;
    // ТОЛЬКО ТЕПЕРЬ помечаем как мертвый
    inherited Dead;
  end;
end;

procedure TSpaceShip.Render;
begin
  inherited Render;

  // Отрисовываем систему частиц, если есть активные частицы
if FHitParticleSystem.count > 0 then
 // begin

    R3D_DrawParticleSystem(@FHitParticleSystem, @FHitParticleMesh, @FHitParticleMaterial);
 // end;
end;

{ TAiShip }

function TAiShip.CalculateRollInput(CurrentUp, TargetUp: TVector3): Single;
var
  CrossProduct: TVector3;
  DotProduct: Single;
begin
  CrossProduct := Vector3CrossProduct(CurrentUp, TargetUp);
  DotProduct := Vector3DotProduct(GetForward(), CrossProduct);
  Result := Clamp(DotProduct, -1, 1);
end;

function TAiShip.CalculatePitchInput(CurrentForward, TargetDirection: TVector3
  ): Single;
var
  ProjectedForward, ProjectedTarget: TVector3;
  Angle: Single;
begin
  // Проецируем на вертикальную плоскость
  ProjectedForward := Vector3Create(CurrentForward.x, 0, CurrentForward.z);
  ProjectedForward := Vector3Normalize(ProjectedForward);
  ProjectedTarget := Vector3Create(TargetDirection.x, 0, TargetDirection.z);
  ProjectedTarget := Vector3Normalize(ProjectedTarget);

  Angle := ArcSin(CurrentForward.y) - ArcSin(TargetDirection.y);
  Result := Clamp(Angle * 2, -1, 1);
end;

function TAiShip.CalculateYawInput(CurrentForward, TargetDirection: TVector3
  ): Single;
var
  CrossProduct: TVector3;
  DotProduct: Single;
begin
  CrossProduct := Vector3CrossProduct(CurrentForward, TargetDirection);
  DotProduct := Vector3DotProduct(Vector3Create(0, 1, 0), CrossProduct);
  Result := Clamp(DotProduct, -1, 1);
end;

constructor TAiShip.Create(const AParent: TSpaceEngine);
begin
  inherited Create(AParent);//, FileName);
  R3D_SetModelImportScale(0.1);

  ColliderType:= ctBox;

  DoCollision := True;
  AlignToHorizon:=False;

  MaxSpeed:=2;
  ShipType := Pirate;
  TrailColor := RED;
  // Настройки стрельбы
  FFireRate := 1.0; // Медленная стрельба
  FLastFireTime := 0;
  FFireRange := 150.0;

  // Настройки плавности управления
  ThrottleResponse := 5;  // Уменьшаем отзывчивость двигателя
  TurnResponse := 5;      // Уменьшаем отзывчивость поворотов
  TurnRate := 120;        // Уменьшаем скорость поворота

end;

procedure TAiShip.Update(const DeltaTime: Single);
var
  Gate: TSpaceGate;
  OrbitHeight: Single;
  Angle, Dist: Single;
  TargetPos, OrbitNormal, RightVector, ToTarget, Dir, EscapeDirection: TVector3;
  DistanceToTarget: Single;
  AvoidanceForce: TVector3;
  i: Integer;

  Player: TSpaceActor;
  DistanceToPlayer: Single;
  PlayerAvoidanceForce: TVector3;
  IsTooCloseToPlayer: Boolean;
  IsMediumCloseToPlayer: Boolean;

  // Новые переменные для плавного управления
  SmoothFactor: Single;

begin
  inherited Update(DeltaTime);

  // Инициализация параметров орбиты при первом вызове
  if FOrbitRadius = 0 then
  begin
    FOrbitRadius := 160 + Random(220);
    FOrbitHeight := -100 + Random(100);
    FOrbitSpeed := 0.2 + Random * 0.2;
    FTargetOrbitHeight := FOrbitHeight;
  end;

  // Поиск SpaceGate в сцене
  Gate := nil;
  for i := 0 to Engine.Count - 1 do
  begin
    if Engine.Items[i] is TSpaceGate then
    begin
      Gate := TSpaceGate(Engine.Items[i]);
      Break;
    end;
  end;

  if Gate = nil then
  begin  // если не нашли просто летим
    InputForward := 0.5;
    Exit;
  end;

  // Поиск игрока
  Player := nil;
  for i := 0 to Engine.Count - 1 do
  begin
    if (Engine.Items[i] is TSpaceShip) and (Engine.Items[i] <> Self) then
    begin
      Player := Engine.Items[i];
      Break;
    end;
  end;

  // Проверяем дистанцию до игрока
  IsTooCloseToPlayer := False;
  IsMediumCloseToPlayer := False;
  if Player <> nil then
  begin
    DistanceToPlayer := Vector3Distance(Position, Player.Position);
    IsTooCloseToPlayer := DistanceToPlayer < 15;
    IsMediumCloseToPlayer := DistanceToPlayer < 30;
  end;

  // Сбрасываем управление
  InputLeft := 0;
  InputUp := 0;
  InputPitchDown := 0;
  InputRollRight := 0;
  InputYawLeft := 0;

  // Если слишком близко к игроку - режим побега
  if IsTooCloseToPlayer then
  begin
    // Вычисляем направление для побега (от игрока)
    EscapeDirection := Vector3Normalize(Vector3Subtract(Position, Player.Position));

    // Цель побега - точка в направлении от игрока
    TargetPos := Vector3Add(Position, Vector3Scale(EscapeDirection, 50));

    // ПЛАВНОЕ управление для побега
    ToTarget := Vector3Subtract(TargetPos, Position);
    ToTarget := Vector3Normalize(ToTarget);

    // Вычисляем необходимые повороты
    SmoothFactor := 0.8; // Коэффициент плавности

    // Рыскание (Yaw) - поворот влево/вправо
    InputYawLeft := CalculateYawInput(GetForward(), ToTarget) * SmoothFactor;

    // Тангаж (Pitch) - наклон вверх/вниз
    InputPitchDown := CalculatePitchInput(GetForward(), ToTarget) * SmoothFactor;

    // Крен (Roll) - для плавного выравнивания
    InputRollRight := CalculateRollInput(GetUp(), Vector3Create(0, 1, 0)) * SmoothFactor * 0.5;

    // Ускоряемся для побега
    InputForward := 0.6;

    // Визуальный эффект
   // ActorModel.materials[1].emission.energy := 350.0;
  end
  else
  begin
    // Обычное поведение (орбита)
    FOrbitAngleChangeTimer += DeltaTime;
    if FOrbitAngleChangeTimer > 8.0 then
    begin
      FOrbitAngleChangeTimer := 0;
      FTargetOrbitHeight := 5 + Random(25);
    end;
    OrbitHeight := SmoothDamp(FOrbitHeight, FTargetOrbitHeight, 0.3, DeltaTime);
    FOrbitHeight := OrbitHeight;

    // Вычисление позиции на орбите
    Angle := GetTime() * FOrbitSpeed;
    OrbitNormal := Vector3Create(0, 1, 0);

    RightVector := Vector3Normalize(Vector3CrossProduct(OrbitNormal, Vector3Create(0, 0, 1)));
    TargetPos := Vector3Add(Gate.Position,
      Vector3Add(
        Vector3Scale(RightVector, FOrbitRadius * Cos(Angle)),
        Vector3Scale(Vector3Normalize(Vector3CrossProduct(RightVector, OrbitNormal)), FOrbitRadius * Sin(Angle)))
      );
    TargetPos.y := Gate.Position.y + OrbitHeight;

    // Избегание препятствий
    AvoidanceForce := Vector3Zero();
    PlayerAvoidanceForce := Vector3Zero();

    if Player <> nil then
    begin
      Dist := Vector3Distance(Position, Player.Position);
      if Dist < 25 then
      begin
        Dir := Vector3Normalize(Vector3Subtract(Position, Player.Position));
        PlayerAvoidanceForce := Vector3Add(PlayerAvoidanceForce,
          Vector3Scale(Dir, 0.8 - (Dist / 25)));
      end;
    end;

    for i := 0 to Engine.Count - 1 do
    begin
      if (Engine.Items[i] <> Self) and (Engine.Items[i] <> Gate) and (Engine.Items[i] <> Player) then
      begin
        Dist := Vector3Distance(Position, Engine.Items[i].Position);
        if Dist < 25 then
        begin
          Dir := Vector3Normalize(Vector3Subtract(Position, Engine.Items[i].Position));
          AvoidanceForce := Vector3Add(AvoidanceForce,
            Vector3Scale(Dir, 0.6 - (Dist / 25)));
        end;
      end;
    end;

    if Vector3Length(PlayerAvoidanceForce) > 0 then
    begin
      PlayerAvoidanceForce := Vector3Normalize(PlayerAvoidanceForce);
      TargetPos := Vector3Add(TargetPos, Vector3Scale(PlayerAvoidanceForce, 15));
    end;

    if Vector3Length(AvoidanceForce) > 0 then
    begin
      AvoidanceForce := Vector3Normalize(AvoidanceForce);
      TargetPos := Vector3Add(TargetPos, Vector3Scale(AvoidanceForce, 12));
    end;

    // Направление к цели
    ToTarget := Vector3Subtract(TargetPos, Position);
    DistanceToTarget := Vector3Length(ToTarget);

    // ПЛАВНОЕ управление для следования за целью
    ToTarget := Vector3Normalize(ToTarget);
    SmoothFactor := 0.6;

    InputYawLeft := CalculateYawInput(GetForward(), ToTarget) * SmoothFactor;
    InputPitchDown := CalculatePitchInput(GetForward(), ToTarget) * SmoothFactor;
    InputRollRight := CalculateRollInput(GetUp(), Vector3Create(0, 1, 0)) * SmoothFactor * 0.3;

    // Управление скоростью
    if IsMediumCloseToPlayer then
    begin
      InputForward := 0.5;//Max(0.3, DistanceToTarget / FOrbitRadius * 0.6);
    end
    else if DistanceToTarget > FOrbitRadius * 0.4 then
    begin
      InputForward := 0.6;//Min(0.6, DistanceToTarget / FOrbitRadius)
    end
    else
    begin
      InputForward := 0.4;// + 0.06 * Sin(GetTime() * 2);
    end;

    // Плавное изменение радиуса орбиты
    if FOrbitChangeTimer > 10.0 then
    begin
      FOrbitChangeTimer := 0;
      FTargetOrbitRadius := 30 + Random(40);
    end;
    FOrbitChangeTimer += DeltaTime;
    FOrbitRadius := SmoothDamp(FOrbitRadius, FTargetOrbitRadius, 0.2, DeltaTime);

    // Стрельба по игроку
    if (Player <> nil) and (not IsTooCloseToPlayer) then
    begin
      DistanceToPlayer := Vector3Distance(Position, Player.Position);
      if DistanceToPlayer < FFireRange then
      begin
        // Плавный поворот к игроку для стрельбы
        ToTarget := Vector3Normalize(Vector3Subtract(Player.Position, Position));
        InputYawLeft := CalculateYawInput(GetForward(), ToTarget) * 0.4;
        InputPitchDown := CalculatePitchInput(GetForward(), ToTarget) * 0.4;

        Shot;
      end;
    end;
  end;
end;








{ TSpaceGate }

constructor TSpaceGate.Create(const AParent: TSpaceEngine);
begin

  inherited Create(AParent);
  R3D_SetModelImportScale(0.05);
  BodyModel := R3D_LoadModel(('data' + '/models/Gate_body.glb'));
  RingModel := R3D_LoadModel(('data' + '/models/Gate_ring.glb'));

   ShipType := Station; // Важно: устанавливаем тип Station
   Position := Vector3Create(10, -100, 100);
   OriginalPosition := Position; // Сохраняем оригинальную позицию
   ColliderType := ctBox;
   ActorModel := BodyModel;
   DoCollision := True;
   AlignToHorizon := False;
   MaxSpeed := 0; // Статический объект

   Ring := TSpaceActor.Create(AParent);
   Ring.Position := Self.Position;
   Ring.DoCollision := False;
   Ring.ActorModel := RingModel;
   Ring.AlignToHorizon := False;
   Ring.MaxSpeed := 0;
   Ring.ShipType := Station; // И кольцо тоже статическое
end;

procedure TSpaceGate.Update(const DeltaTime: Single);
const
  MinEnergy = 30;
  MaxEnergy = 70;
  PulseDuration = 1.0; // Полный цикл за 1 сек
var
  PulseFactor: Single;
  IsStaticObject: Boolean;
begin
  inherited Update(DeltaTime);

    // ФИКСИРУЕМ ПОЗИЦИЮ ПЕРЕД ОБНОВЛЕНИЕМ
  FixPosition;
  // Проверяем, является ли объект статическим
  IsStaticObject := (MaxSpeed = 0) or (ShipType = Station);

  // Только движущиеся объекты обновляют позицию через velocity
  if not IsStaticObject then
  begin
    // Обновляем позицию на основе скорости
    Position := Vector3Add(Position, Vector3Scale(Velocity, DeltaTime));
  end;

   Ring.Position := Self.Position;
   Ring.RotateLocalEuler(Vector3Create(0, 1, 0), 30 * DeltaTime);

   // Плавное колебание с помощью Lerp
   PulseFactor := (Sin(GetTime() * (PI/PulseDuration)) + 1) * 0.5; // 0..1

   Ring.ActorModel.materials[1].emission.color := BLUE;
   Ring.ActorModel.materials[1].emission.energy := Lerp(MinEnergy, MaxEnergy, PulseFactor);
   Ring.ActorModel.materials[1].albedo.color := BLACK;
    // ФИКСИРУЕМ ПОЗИЦИЮ  ОБНОВЛЕНИЕМ
  FixPosition;
end;

{ TScreenSpace }



procedure TScreenSpace.Init;
var i: integer;
begin
  Engine := TSpaceEngine.Create;
  Engine.CrosshairFar.Create('data' + '/models/UI/crosshair2.gltf');
  Engine.CrosshairNear.Create('data' + '/models/UI/crosshair.gltf');
  Engine.LoadSkyBox('data' +'/skybox/planets/earthlike_planet_close.hdr', SQHigh, STPanorama);


  Engine.EnableSkybox;
  Engine.Light[0] := R3D_CreateLight(R3D_LIGHT_DIR);

  R3D_LightLookAt(Engine.Light[0], Vector3Create( 0, 10, 5 ), Vector3Create(0,0,0));
  R3D_SetLightActive(Engine.Light[0], true);
  R3D_EnableShadow(Engine.Light[0], 4096);

  R3D_SetModelImportScale(1.1);
  R3D_SetBrightness(3);


  Camera := TSpaceCamera.Create(True, 50);

  for i := 0 to 5 do
  begin
    R3D_SetModelImportScale(0.1);
    ShipModel[i] := R3D_LoadModel('data/models/test.glb');
  end;

  Ship := TSpaceShip.Create(Engine); //, 'data/models/test.glb');
  Ship.ActorModel := ShipModel[5];
  Ship.NumMatEngine:=1;
  Ship.Energy:=100000;
  Gate := TSpaceGate.Create(Engine);

  for i := 0 to 4 do
  begin
    AiShip[i] := TAiShip.Create(Engine);//, ('data/models/test.glb'));
    AiShip[i].ActorModel := ShipModel[i];
    AiShip[i].MaxSpeed:= GetRandomValue(5,15);
    AiShip[i].Position := VEctor3Create(GetRandomValue(-100,100), GetRandomValue(-100,100),GetRandomValue(-100,100));
    AiShip[i].TrailColor := RED;
    AiShip[i].ShotColor := GREEN;
    AiShip[i].NumMatEngine := 1;
    AiShip[i].Energy:=10;
  end;



  // При старте игры или активации корабля
 // DisableCursor(); // Скрыть курсор
  SetMousePosition(GetScreenWidth div 2, GetScreenHeight div 2);

  Engine.Radar.Player := Ship;

   Ship.Position := Vector3Create(100,100,100);

  end;

procedure TScreenSpace.Shutdown;
begin
  Engine.Destroy;
  // R3D_UnloadModel(@ShipModel, true);
end;

procedure TScreenSpace.Update(MoveCount: Single);
var
  i: Integer;
begin

  // Проверяем уничтоженные и невидимые объекты
  for i := Engine.Count - 1 downto 0 do
  begin
    if (Engine.Items[i].IsDead) or
       (not Engine.Items[i].Visible) then
    begin
      Engine.Items[i].Free;
    end;
  end;



  Engine.Update(MoveCount, Ship.Position);

  Engine.ClearDeadActor;
  Engine.Collision;

  Engine.ApplyInputToShip(Ship, 0.5);


  Camera.FollowActor(Ship, MoveCount);

  Engine.CrosshairFar.PositionCrosshairOnActor(Ship, 20);
  Engine.CrosshairNear.PositionCrosshairOnActor(Ship, 15);
end;

procedure TScreenSpace.Render;
begin
  inherited Render;
  BeginDrawing();
    ClearBackground( ColorCreate(32, 32, 64, 255) );
    {$IFDEF DEBUG}
    Engine.Render(Camera,True,True,Ship.Velocity,False);
    DrawFPS(10,10);
    {$ELSE}
    Engine.Render(Camera,False,False,Ship.Velocity,False);
    {$ENDIF}
    DrawFPS(10,10);
  EndDrawing();
end;

procedure TScreenSpace.Show;
begin
  inherited Show;
end;

procedure TScreenSpace.Hide;
begin
  inherited Hide;
end;

end.

