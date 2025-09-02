unit ScreenSpace;

{$mode ObjFPC}{$H+}
{$define DEBUG}


interface

uses
  RayLib, RayMath, Classes, SysUtils, Collider, ScreenManager, SpaceEngine, DigestMath, r3d, Math;

{ TSpaceShip }
type
  TSpaceShip = class(TSpaceActor)
  private

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
  end;


    { TPlanet }
    TPlanet = class(TSpaceActor)
    private
      FBloom: Boolean;
      FBloomBlink: Boolean;
      FBloomColor: TColorB;
      FBloomEnergy: Single;
      FBloomMatIndex: Integer;
      FBlooom: Boolean;
     // Ring: TSpaceActor;  // todo
    //  BodyModel, RingModel: TR3D_Model;
    public
      constructor Create(const AParent: TSpaceEngine); override;
      procedure Update(const DeltaTime: Single); override;
      property Bloom: Boolean read FBlooom write FBloom;
      property BloomColor: TColorB read FBloomColor write FBloomColor;
      property BloomMatIndex: Integer read FBloomMatIndex write FBloomMatIndex;
      property BloomBlink: Boolean read FBloomBlink write FBloomBlink;
      property BloomEnergy: Single read FBloomEnergy write FBloomEnergy;
    end;

  { TBaseAiShip }
  TBaseAiShip = class(TSpaceShip)
  protected
    FOrbitRadius: Single;
    FOrbitHeight: Single;
    FOrbitSpeed: Single;
    FOrbitAngleChangeTimer: Single;
    FTargetOrbitHeight: Single;
    FTargetOrbitRadius: Single;
    FCurrentPlanet: TPlanet;

    function FindNearestPlanet: TPlanet;
    function CalculateRollInput(CurrentUp, TargetUp: TVector3): Single;
    function CalculatePitchInput(CurrentForward, TargetDirection: TVector3): Single;
    function CalculateYawInput(CurrentForward, TargetDirection: TVector3): Single;
    function IsFacingTarget(TargetPos: TVector3; MaxAngleDegrees: Single): Boolean;
    procedure UpdateOrbitalBehavior(DeltaTime: Single);

  public
    constructor Create(const AParent: TSpaceEngine); override;
    procedure Update(const DeltaTime: Single); override;
  end;


  { TNeutralTraderShip }
  TNeutralTraderShip = class(TBaseAiShip)
  private
    FDestinationPlanet: TPlanet;
    FTravelTimer: Single;
    FState: (tsOrbiting, tsTraveling);
    FOrbitTime: Single;
    FMaxOrbitTime: Single;

    procedure FindDestinationPlanet;
    procedure UpdateOrbitingBehavior(DeltaTime: Single);
    procedure UpdateTravelingBehavior(DeltaTime: Single);

  public
    constructor Create(const AParent: TSpaceEngine); override;
    procedure Update(const DeltaTime: Single); override;
  end;

  { TPirateShip }
  TPirateState = (psPatrolling, psChasing, psAttacking, psEvading);

  TPirateShip = class(TBaseAiShip)
  private
    FDetectionRange: Single;
    FAttackRange: Single;
    FEvadeRange: Single;
    FTarget: TSpaceActor;
    FState: TPirateState;//(psPatrolling, psChasing, psAttacking, psEvading);
    FStateTimer: Single;
    FMaxPatrolTime: Single;

    procedure FindTarget;
    procedure UpdatePatrollingBehavior(DeltaTime: Single);
    procedure UpdateChasingBehavior(DeltaTime: Single);
    procedure UpdateAttackingBehavior(DeltaTime: Single);
    procedure UpdateEvadingBehavior(DeltaTime: Single);
    procedure ChangeState(NewState: TPirateState);//(psPatrolling, psChasing, psAttacking, psEvading));

  public
    constructor Create(const AParent: TSpaceEngine); override;
    procedure Update(const DeltaTime: Single); override;
    procedure OnCollision(const Actor: TSpaceActor); override;
  end;

  { TScreenSpace }

  TScreenSpace = class(TGameScreen)
  private
    Engine: TSpaceEngine;
    PiratesModel:  array[0..4] of TR3D_Model;
    PlayerModel: TR3D_Model;
    PlanetModel: TR3D_Model;
    Ship: TSpaceShip;
    AiShip: array[0..5] of TPirateShip;
    AiShip2: array[0..5] of TNeutralTraderShip;
    Planets: TPlanet;
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



  ColliderType:= ctBox;
  ActorModel := Default(TR3D_Model);
  DoCollision := True;
  AlignToHorizon:=False;
  MaxSpeed:=20;

  // Настройки стрельбы
  FFireRate := 3.0;
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

  EnergyOfLife := 100;

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
  StartPos := Vector3Add(Position, GetForward);

  // Создаем снаряд с указанием владельца (this)
  TImpulseLazer.Create(Engine, Self, StartPos, GetForward(), 100.0, 25.0, ShotColor);
end;

procedure TSpaceShip.OnCollision(const Actor: TSpaceActor);
var
  HitPos, HitNorm: TVector3;
  Damage: Single;
  LazerColor: TColorB;
begin
  inherited OnCollision(Actor);

  // Проверяем, что это снаряд врага
    if (Actor is TImpulseLazer) and (TImpulseLazer(Actor).Owner <> Self) then
  begin
    // Получаем цвет лазера
    LazerColor := TImpulseLazer(Actor).TrailColor;

    // Вычисляем точку попадания
    HitPos := Vector3Lerp(Position, Actor.Position, 0.3);
    HitNorm := Vector3Normalize(Vector3Subtract(Position, Actor.Position));

    // Наносим урон
    Damage := Actor.Tag;
    EnergyOfLife := EnergyOfLife - Trunc(Damage);
   // If Energy <= 0 then FIsDying := True;
      // Проверяем условие смерти
    if (EnergyOfLife <= 0) and not IsDead then
    begin
       StartDeathSequence;
    end;

    LazerColor :=  TImpulseLazer(Actor).TrailColor;

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
  ActorCollison := False;
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

{ TBaseAiShip }
constructor TBaseAiShip.Create(const AParent: TSpaceEngine);
begin
  inherited Create(AParent);

  ColliderType := ctBox;
  DoCollision := True;
  AlignToHorizon := False;
  MaxSpeed := 8;
  FFireRate := 2.0;
  FLastFireTime := 0;

  // Инициализация параметров орбиты
  FOrbitRadius := 0;
  FOrbitHeight := 0;
  FOrbitSpeed := 0.2;
  FCurrentPlanet := nil;
end;

procedure TBaseAiShip.Update(const DeltaTime: Single);
begin
  inherited Update(DeltaTime);

  // Базовая логика орбитального движения
  UpdateOrbitalBehavior(DeltaTime);
end;

function TBaseAiShip.FindNearestPlanet: TPlanet;
var
  i: Integer;
  Actor: TSpaceActor;
  Distance, MinDistance: Single;
begin
  Result := nil;
  MinDistance := 1000.0;

  for i := 0 to Engine.Count - 1 do
  begin
    Actor := Engine.Items[i];
    if (Actor is TPlanet) and not Actor.IsDead then
    begin
      Distance := Vector3Distance(Position, Actor.Position);
      if Distance < MinDistance then
      begin
        MinDistance := Distance;
        Result := TPlanet(Actor);
      end;
    end;
  end;
end;

procedure TBaseAiShip.UpdateOrbitalBehavior(DeltaTime: Single);
var
  Angle: Single;
  TargetPos, ToTarget: TVector3;
  DistanceToTarget: Single;
begin
  // Поиск ближайшей планеты
  if FCurrentPlanet = nil then
    FCurrentPlanet := FindNearestPlanet;

  if FCurrentPlanet = nil then
  begin
    // Просто летим вперед, если нет планеты
    InputForward := 0.3;
    Exit;
  end;

  // Инициализация параметров орбиты при первом вызове
  if FOrbitRadius = 0 then
  begin
    FOrbitRadius := 160 + Random(220);
    FOrbitHeight := -50 + Random(100);
    FOrbitSpeed := 0.1 + Random * 0.3;
    FTargetOrbitHeight := FOrbitHeight;
  end;

  // Плавное изменение высоты орбиты
  FOrbitAngleChangeTimer := FOrbitAngleChangeTimer + DeltaTime;
  if FOrbitAngleChangeTimer > 10.0 then
  begin
    FOrbitAngleChangeTimer := 0;
    FTargetOrbitHeight := -30 + Random(80);
  end;
  FOrbitHeight := SmoothDamp(FOrbitHeight, FTargetOrbitHeight, 0.2, DeltaTime);

  // Вычисление позиции на орбите
  Angle := GetTime() * FOrbitSpeed;
  TargetPos := Vector3Add(FCurrentPlanet.Position,
    Vector3Create(
      FOrbitRadius * Cos(Angle),
      FOrbitHeight,
      FOrbitRadius * Sin(Angle)
    )
  );

  // Направление к цели
  ToTarget := Vector3Subtract(TargetPos, Position);
  DistanceToTarget := Vector3Length(ToTarget);
  ToTarget := Vector3Normalize(ToTarget);

  // Плавное управление
  InputYawLeft := CalculateYawInput(GetForward(), ToTarget) * 0.5;
  InputPitchDown := CalculatePitchInput(GetForward(), ToTarget) * 0.5;
  InputRollRight := CalculateRollInput(GetUp(), Vector3Create(0, 1, 0)) * 0.3;

  // Управление скоростью
  if DistanceToTarget > FOrbitRadius * 0.3 then
    InputForward := 0.7
  else
    InputForward := 0.4;
end;

function TBaseAiShip.CalculateRollInput(CurrentUp, TargetUp: TVector3): Single;
var
  CrossProduct: TVector3;
begin
  CrossProduct := Vector3CrossProduct(CurrentUp, TargetUp);
  Result := Clamp(Vector3DotProduct(GetForward(), CrossProduct), -1, 1);
end;

function TBaseAiShip.CalculatePitchInput(CurrentForward, TargetDirection: TVector3): Single;
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

function TBaseAiShip.CalculateYawInput(CurrentForward, TargetDirection: TVector3): Single;
var
  CrossProduct: TVector3;
begin
  CrossProduct := Vector3CrossProduct(CurrentForward, TargetDirection);
  Result := Clamp(Vector3DotProduct(Vector3Create(0, 1, 0), CrossProduct), -1, 1);
end;

function TBaseAiShip.IsFacingTarget(TargetPos: TVector3; MaxAngleDegrees: Single): Boolean;
var
  ToTarget, ForwardDir: TVector3;
  DotProduct, AngleRad: Single;
begin
  ForwardDir := GetForward();
  ToTarget := Vector3Normalize(Vector3Subtract(TargetPos, Position));

  DotProduct := Vector3DotProduct(ForwardDir, ToTarget);
  AngleRad := ArcCos(Clamp(DotProduct, -1, 1));

  Result := (AngleRad * RAD2DEG) <= MaxAngleDegrees;
end;



constructor TNeutralTraderShip.Create(const AParent: TSpaceEngine);
begin
  inherited Create(AParent);

  ShipStatus := ss_Neutral;
  TrailColor := BLUE;
  ShotColor := GREEN;
  FState := tsOrbiting;
  FOrbitTime := 0;
  FMaxOrbitTime := 15 + Random(30);
  FTravelTimer := 0;
end;

procedure TNeutralTraderShip.Update(const DeltaTime: Single);
begin
  inherited Update(DeltaTime);

  case FState of
    tsOrbiting: UpdateOrbitingBehavior(DeltaTime);
    tsTraveling: UpdateTravelingBehavior(DeltaTime);
  end;
end;

procedure TNeutralTraderShip.UpdateOrbitingBehavior(DeltaTime: Single);
begin
  // Увеличиваем время на орбите
  FOrbitTime := FOrbitTime + DeltaTime;

  // Если достаточно наорбитились, ищем новую цель
  if FOrbitTime >= FMaxOrbitTime then
  begin
    FindDestinationPlanet;
    if FDestinationPlanet <> nil then
    begin
      FState := tsTraveling;
      FTravelTimer := 0;
      FOrbitTime := 0;
      FMaxOrbitTime := 20 + Random(40);
    end;
  end;

  // Вызываем базовое орбитальное поведение
  inherited UpdateOrbitalBehavior(DeltaTime);
end;

procedure TNeutralTraderShip.UpdateTravelingBehavior(DeltaTime: Single);
var
  ToDestination: TVector3;
  Distance: Single;
begin
  if FDestinationPlanet = nil then
  begin
    FState := tsOrbiting;
    Exit;
  end;

  // Направление к планете назначения
  ToDestination := Vector3Subtract(FDestinationPlanet.Position, Position);
  Distance := Vector3Length(ToDestination);
  ToDestination := Vector3Normalize(ToDestination);

  // Управление кораблем
  InputYawLeft := CalculateYawInput(GetForward(), ToDestination) * 0.7;
  InputPitchDown := CalculatePitchInput(GetForward(), ToDestination) * 0.7;
  InputRollRight := CalculateRollInput(GetUp(), Vector3Create(0, 1, 0)) * 0.4;

  // Управление скоростью
  if Distance > 200 then
    InputForward := 0.8
  else if Distance < 50 then
  begin
    // Прибыли к цели
    FCurrentPlanet := FDestinationPlanet;
    FDestinationPlanet := nil;
    FState := tsOrbiting;
    InputForward := 0.3;
  end
  else
    InputForward := 0.5;

  // Таймер безопасности - если долго летим, возвращаемся на орбиту
  FTravelTimer := FTravelTimer + DeltaTime;
  if FTravelTimer > 60 then
  begin
    FState := tsOrbiting;
    FTravelTimer := 0;
  end;
end;

procedure TNeutralTraderShip.FindDestinationPlanet;
var
  i: Integer;
  Actor: TSpaceActor;
  CandidatePlanets: array of TPlanet;
begin
  FDestinationPlanet := nil;
  SetLength(CandidatePlanets, 0);

  // Собираем все планеты кроме текущей
  for i := 0 to Engine.Count - 1 do
  begin
    Actor := Engine.Items[i];
    if (Actor is TPlanet) and (Actor <> FCurrentPlanet) and not Actor.IsDead then
    begin
      SetLength(CandidatePlanets, Length(CandidatePlanets) + 1);
      CandidatePlanets[High(CandidatePlanets)] := TPlanet(Actor);
    end;
  end;

  // Выбираем случайную планету
  if Length(CandidatePlanets) > 0 then
    FDestinationPlanet := CandidatePlanets[Random(Length(CandidatePlanets))];
end;

constructor TPirateShip.Create(const AParent: TSpaceEngine);
begin
  inherited Create(AParent);

  ShipStatus := ssPirate;
  TrailColor := RED;
  ShotColor := RED;
  FState := psAttacking;

  FDetectionRange := 300.0;
  FAttackRange := 200.0;
  FEvadeRange := 150.0;
  FStateTimer := 0;
  FMaxPatrolTime := 30 + Random(30);
end;

procedure TPirateShip.Update(const DeltaTime: Single);
begin
  inherited Update(DeltaTime);

  FStateTimer := FStateTimer + DeltaTime;

  // Автоматический возврат к патрулированию через некоторое время
  if (FState <> psPatrolling) and (FStateTimer > 45) then
    ChangeState(psPatrolling);

  case FState of
    psPatrolling: UpdatePatrollingBehavior(DeltaTime);
    psChasing: UpdateChasingBehavior(DeltaTime);
    psAttacking: UpdateAttackingBehavior(DeltaTime);
    psEvading: UpdateEvadingBehavior(DeltaTime);
  end;
end;

procedure TPirateShip.OnCollision(const Actor: TSpaceActor);
begin
  inherited OnCollision(Actor);

  // Если в пирата попали, он становится агрессивным
  if (Actor is TImpulseLazer) and (TImpulseLazer(Actor).Owner <> Self) then
  begin
    FTarget := TImpulseLazer(Actor).Owner;
    ChangeState(psAttacking);
  end;
end;

procedure TPirateShip.ChangeState(NewState: TPirateState);//(psPatrolling, psChasing, psAttacking, psEvading));
begin
  if FState = NewState then Exit;

  FState := NewState;
  FStateTimer := 0;

  case NewState of
    psPatrolling: FMaxPatrolTime := 20 + Random(40);
    psAttacking: MaxSpeed := 12; // Повышаем скорость в атаке
    else MaxSpeed := 8;
  end;
end;

procedure TPirateShip.FindTarget;
var
  i: Integer;
  Actor: TSpaceActor;
  Distance, MinDistance: Single;
begin
  FTarget := nil;
  MinDistance := FDetectionRange;

  for i := 0 to Engine.Count - 1 do
  begin
    Actor := Engine.Items[i];

    // Ищем торговые корабли и игрока
    if (Actor <> Self) and not Actor.IsDead and
       ((Actor is TNeutralTraderShip) or (Actor is TSpaceShip)) and
       (Actor.ShipStatus <> ssPirate) then
    begin
      Distance := Vector3Distance(Position, Actor.Position);
      if Distance < MinDistance then
      begin
        MinDistance := Distance;
        FTarget := Actor;
      end;
    end;
  end;
end;

procedure TPirateShip.UpdatePatrollingBehavior(DeltaTime: Single);
begin
  // Периодически ищем цели
  if FStateTimer > 5 then
  begin
    FindTarget;
    if FTarget <> nil then
    begin
      ChangeState(psChasing);
      Exit;
    end;
    FStateTimer := 0;
  end;

  // Базовое орбитальное поведение
  inherited UpdateOrbitalBehavior(DeltaTime);

  // Случайно меняем параметры орбиты для более естественного патрулирования
  if FStateTimer > 10 then
  begin
    FOrbitRadius := 120 + Random(180);
    FOrbitHeight := -40 + Random(80);
    FStateTimer := 0;
  end;
end;

procedure TPirateShip.UpdateChasingBehavior(DeltaTime: Single);
var
  ToTarget: TVector3;
  Distance: Single;
begin
  if (FTarget = nil) or FTarget.IsDead then
  begin
    ChangeState(psPatrolling);
    Exit;
  end;

  ToTarget := Vector3Subtract(FTarget.Position, Position);
  Distance := Vector3Length(ToTarget);
  ToTarget := Vector3Normalize(ToTarget);

  // Преследование цели
  InputYawLeft := CalculateYawInput(GetForward(), ToTarget) * 0.8;
  InputPitchDown := CalculatePitchInput(GetForward(), ToTarget) * 0.8;
  InputRollRight := CalculateRollInput(GetUp(), Vector3Create(0, 1, 0)) * 0.5;

  // Управление скоростью
  if Distance > FAttackRange then
    InputForward := 0.9
  else
  begin
    ChangeState(psAttacking);
    InputForward := 0.6;
  end;
end;

procedure TPirateShip.UpdateAttackingBehavior(DeltaTime: Single);
var
  ToTarget: TVector3;
  Distance: Single;
begin
  if (FTarget = nil) or FTarget.IsDead then
  begin
    ChangeState(psPatrolling);
    Exit;
  end;

  ToTarget := Vector3Subtract(FTarget.Position, Position);
  Distance := Vector3Length(ToTarget);
  ToTarget := Vector3Normalize(ToTarget);

  // Атака цели
  InputYawLeft := CalculateYawInput(GetForward(), ToTarget) * 0.9;
  InputPitchDown := CalculatePitchInput(GetForward(), ToTarget) * 0.9;
  InputRollRight := CalculateRollInput(GetUp(), Vector3Create(0, 1, 0)) * 0.6;

  // Управление скоростью и стрельба
  if Distance > FAttackRange * 0.8 then
    InputForward := 0.8
  else if Distance < FAttackRange * 0.4 then
    InputForward := 0.4
  else
    InputForward := 0.6;

  // Стрельба при возможности
  if (Distance < FAttackRange) and IsFacingTarget(FTarget.Position, 12) then
    Shot;

  // Проверка на отступление
  if (EnergyOfLife < 30) or (Distance < FEvadeRange) then
    ChangeState(psEvading);
end;

procedure TPirateShip.UpdateEvadingBehavior(DeltaTime: Single);
var
  EscapeDirection: TVector3;
begin
  if FTarget = nil then
  begin
    ChangeState(psPatrolling);
    Exit;
  end;

  // Направление для побега (от цели)
  EscapeDirection := Vector3Normalize(Vector3Subtract(Position, FTarget.Position));

  // Управление для побега
  InputYawLeft := CalculateYawInput(GetForward(), EscapeDirection) * 0.9;
  InputPitchDown := CalculatePitchInput(GetForward(), EscapeDirection) * 0.9;
  InputRollRight := CalculateRollInput(GetUp(), Vector3Create(0, 1, 0)) * 0.7;

  // Максимальная скорость для побега
  InputForward := 1.0;

  // Возврат к патрулированию после отступления
  if FStateTimer > 15 then
    ChangeState(psPatrolling);
end;



{ TPlanet }
constructor TPlanet.Create(const AParent: TSpaceEngine);
begin
  inherited Create(AParent);

  //BodyModel := R3D_LoadModel(('data' + '/models/Gate_body.glb'));
 // RingModel := R3D_LoadModel(('data' + '/models/Gate_ring.glb'));

  ShipType := stPlanet; // Важно: устанавливаем тип Station
  ShipStatus := ss_Neutral;
  Position := Vector3Create(0, 0, 0);
  OriginalPosition := Position; // Сохраняем оригинальную позицию
  ColliderType := ctBox;
  //ActorModel := BodyModel;
  DoCollision := True;
  AlignToHorizon := False;
  MaxSpeed := 0; // Статический объект

  FBloom:= False;
  FBloomBlink:= False;
  FBloomMatIndex := 0;
  FBloomEnergy := 70;

  {
   Ring := TSpaceActor.Create(AParent);
   Ring.Position := Self.Position;
   Ring.DoCollision := False;
   Ring.ActorModel := RingModel;
   Ring.AlignToHorizon := False;
   Ring.MaxSpeed := 0;
   Ring.ShipType := stPlanet; // И кольцо тоже статическое }

end;

procedure TPlanet.Update(const DeltaTime: Single);
const
  MinEnergy = 20;
  MaxEnergy = 60;
  PulseDuration = 1.0; // Полный цикл за 1 сек
var
  PulseFactor: Single;
  IsStaticObject: Boolean;
begin
  inherited Update(DeltaTime);

    // ФИКСИРУЕМ ПОЗИЦИЮ ПЕРЕД ОБНОВЛЕНИЕМ
  FixPosition;
  // Проверяем, является ли объект статическим
  IsStaticObject := (MaxSpeed = 0) or (ShipType = stPlanet);

  // Только движущиеся объекты обновляют позицию через velocity
  if not IsStaticObject then
  begin
    // Обновляем позицию на основе скорости
    Position := Vector3Add(Position, Vector3Scale(Velocity, DeltaTime));
  end;

  if FBloom then
  begin
    PulseFactor := (Sin(GetTime() * (PI/PulseDuration)) + 1) * 0.5; // 0..1
    ActorModel.materials[FBloomMatIndex].emission.color := FBloomColor;
    if BloomBlink then ActorModel.materials[FBloomMatIndex].emission.energy := Lerp(MinEnergy, MaxEnergy, PulseFactor)
    else
    ActorModel.materials[FBloomMatIndex].emission.energy := FBloomEnergy;

  end;

   {
   Ring.Position := Self.Position;
   Ring.RotateLocalEuler(Vector3Create(0, 1, 0), 30 * DeltaTime);

   // Плавное колебание с помощью Lerp
   PulseFactor := (Sin(GetTime() * (PI/PulseDuration)) + 1) * 0.5; // 0..1

   Ring.ActorModel.materials[1].emission.color := BLUE;
   Ring.ActorModel.materials[1].emission.energy := Lerp(MinEnergy, MaxEnergy, PulseFactor);
   Ring.ActorModel.materials[1].albedo.color := BLACK;}

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
  Engine.LoadSkyBox('data' +'/skybox/HDR_blue_local_star.hdr', SQHigh, STPanorama);


  Engine.EnableSkybox;
  Engine.Light[0] := R3D_CreateLight(R3D_LIGHT_DIR);

  R3D_LightLookAt(Engine.Light[0], Vector3Create( 0, 10, 5 ), Vector3Create(0,0,0));
  R3D_SetLightActive(Engine.Light[0], true);
  R3D_EnableShadow(Engine.Light[0], 4096);


  R3D_SetBrightness(3);


  Camera := TSpaceCamera.Create(True, 50);

  for i := 0 to 4 do
  begin

    PiratesModel[i] := R3D_LoadModel('data/models/ships/Spaceship_BarbaraTheBee.glb');
  end;

  playerModel := R3D_LoadModel('data/models/ships/Spaceship_BarbaraTheBee.glb');

  Ship := TSpaceShip.Create(Engine); //, 'data/models/test.glb');
  Ship.ActorModel := PlayerModel;
  Ship.NumMatEngine:=1;
  Ship.EnergyOfLife:=100000;
 // Ship.Scale:=10;


 for i := 0 to 4 do
 begin
   AiShip[i] := TPirateShip.Create(Engine);
   AiShip[i].ActorModel := PiratesModel[0];
   AiShip[i].MaxSpeed := GetRandomValue(5, 15);
   AiShip[i].Position := Vector3Create(GetRandomValue(-100, 100), GetRandomValue(-100, 100), GetRandomValue(-100, 100));
   AiShip[i].TrailColor := BLUE;
   AiShip[i].ShotColor := GREEN;
   AiShip[i].NumMatEngine := 1;
   AiShip[i].EnergyOfLife := 100;
   AiShip[i].ShipType:=stShip_Bee;
   AiShip[i].ShipStatus:=ssPirate;
end;
 
 for i := 0 to 4 do
 begin
   AiShip2[i] := TNeutralTraderShip.Create(Engine);
   AiShip2[i].ActorModel := PiratesModel[0];
   AiShip2[i].MaxSpeed := GetRandomValue(5, 15);
   AiShip2[i].Position := Vector3Create(GetRandomValue(-100, 100), GetRandomValue(-100, 100), GetRandomValue(-100, 100));
   AiShip2[i].TrailColor := BLUE;
   AiShip2[i].ShotColor := GREEN;
   AiShip2[i].NumMatEngine := 1;
   AiShip2[i].EnergyOfLife := 100;
   AiShip2[i].ShipType:=stShip_Bee;
   AiShip2[i].ShipStatus:=ss_Neutral;
end;
 {
 for i := 0 to 18 do
 begin
   AiShip[i] := TAiShip.Create(Engine);
   AiShip[i].ActorModel := PiratesModel[0];
   AiShip[i].MaxSpeed := GetRandomValue(5, 15);
   AiShip[i].Position := Vector3Create(GetRandomValue(-100, 100), GetRandomValue(-100, 100), GetRandomValue(-100, 100));
   AiShip[i].TrailColor := BLUE;
   AiShip[i].ShotColor := GREEN;
   AiShip[i].NumMatEngine := 1;
   AiShip[i].EnergyOfLife := 100;

   if i < 5 then
   begin
     AiShip[i].ShipStatus := ss_Neutral;
     AiShip[i].TrailColor := BLUE;  // Синий для нейтральных
     AiShip[i].ShotColor := GREEN;  // Зеленый для нейтральных
     // Нейтральные корабли могут начинать в нейтральном состоянии
     AiShip[i].ChangeState(asNeutral);
   end
   else
   begin
     AiShip[i].ShipStatus := ssPirate;
     AiShip[i].TrailColor := RED;   // Красный для пиратов
     AiShip[i].ShotColor := RED;    // Красный для пиратов
     // Пираты начинают в агрессивном состоянии
     AiShip[i].ChangeState(asAggressive);
   end;
 end; }
  {
  for i := 5 to 9 do
  begin
    AiShip[i] := TAiShip.Create(Engine);//, ('data/models/test.glb'));
    AiShip[i].ActorModel := PiratesModel[0];
    AiShip[i].MaxSpeed:= GetRandomValue(5,15);
    AiShip[i].Position := VEctor3Create(GetRandomValue(-100,100), GetRandomValue(-100,100),GetRandomValue(-100,100));
    AiShip[i].TrailColor := BLUE;
    AiShip[i].ShotColor := GREEN;
    AiShip[i].NumMatEngine := 1;
    AiShip[i].EnergyOfLife:=100;
     AiShip[i].ShipStatus:=ssPirate;
    AiShip[i].ChangeState(asAggressive);
 //   AiShip[i].Scale:=10;
  end;
  }
  // При старте игры или активации корабля
 // DisableCursor(); // Скрыть курсор
  SetMousePosition(GetScreenWidth div 2, GetScreenHeight div 2);

  Engine.Radar.Player := Ship;

  Ship.Position := Vector3Create(100,100,100);


   planetModel := R3D_LoadModel('data/models/planets/Planet_11.glb');
   Planets := TPlanet.Create(Engine);
   Planets.ActorModel := planetModel;
   //Planet.Scale:= 100;
   Planets.BloomColor := RED;
   Planets.BloomBlink:=True;
   Planets.BloomMatIndex:=1;
   Planets.Bloom:=True;

   Planets.Scale:=50;



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

