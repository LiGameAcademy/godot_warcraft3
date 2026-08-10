# .scn 烘焙覆盖度报告

> 生成时间：2026-08-10T04:41:08.050Z
> 仓库：D:\GodotProject\laoli_gamedev_godot4_course\godot_warcraft3

## 总览

| 指标 | 数值 |
|------|------|
| .glb 总数 | 3289 |
| .scn 总数 | 3070 |
| 覆盖率 | 93.3% |
| 缺漏（glb 缺 scn） | 219 |
| 孤儿（scn 无 glb） | 0 |

## 按分类

| 分类 | .glb | .scn | 覆盖率 | 缺漏 |
|------|------|------|--------|------|
| Buildings | 179 | 172 | 96.1% | 7 |
| Doodads | 1593 | 1583 | 99.4% | 10 |
| Units | 725 | 723 | 99.7% | 2 |
| 其他 | 792 | 592 | 74.7% | 200 |

## 缺漏清单（219 个）

> 这些 glb 缺同 stem .scn；runtime 走 GLTFDocument 解析 + 临时注入 geosetvis。
> 全 bake 命令：`npm run bake:scn -- --force`

### Buildings（7）

- `Buildings/Human/GryphonAviary/GryphonAviary.glb`
- `Buildings/Human/HumanTower/HumanTower.glb`
- `Buildings/Human/TownHall/TownHall.glb`
- `Buildings/NightElf/AltarOfElders/AltarOfElders.glb`
- `Buildings/NightElf/AncientOfLore/AncientofLore.glb`
- `Buildings/NightElf/AncientOfWar/AncientofWar.glb`
- `Buildings/NightElf/AncientOfWind/AncientofWind.glb`

### Doodads（10）

- `Doodads/Cinematic/DemonStorm/DemonStorm.glb`
- `Doodads/Icecrown/Water/BubbleGeyserSteam/BubbleGeyserSteam.glb`
- `Doodads/LordaeronSummer/Water/Shoreline/Shoreline0.glb`
- `Doodads/LordaeronSummer/Water/ShorelineInsideCorner/ShorelineInsideCorner0.glb`
- `Doodads/LordaeronSummer/Water/ShorelineOutsideCorner/ShorelineOutsideCorner0.glb`
- `Doodads/Outland/Water/OutlandShoreline/OutlandShoreline0.glb`
- `Doodads/Ruins/Water/BubbleGeyser/BubbleGeyser.glb`
- `Doodads/Terrain/OutlandMushroomTree/OutlandMushroomTree1D.glb`
- `Doodads/Terrain/OutlandMushroomTree/OutlandMushroomTree8D.glb`
- `Doodads/Terrain/OutlandMushroomTree/OutlandMushroomTree9D.glb`

### Units（2）

- `Units/Undead/PlagueCloud/PlagueCloud.glb`
- `Units/Undead/PlagueCloud/PlagueCloudTarget.glb`

### 其他（200）

- `Abilities/Spells/Human/Banish/BanishTarget.glb`
- `Abilities/Spells/Human/CloudOfFog/CloudOfFog.glb`
- `Abilities/Spells/Human/Feedback/ArcaneTowerAttack.glb`
- `Abilities/Spells/Human/Feedback/SpellBreakerAttack.glb`
- `Abilities/Spells/Human/FlakCannons/FlakTarget.glb`
- `Abilities/Spells/Human/FlameStrike/FlameStrikeDamageTarget.glb`
- `Abilities/Spells/Human/FlameStrike/FlameStrikeEmbers.glb`
- `Abilities/Spells/Human/FlameStrike/FlameStrikeTarget.glb`
- `Abilities/Spells/Human/MarkOfChaos/MarkOfChaosDone.glb`
- `Abilities/Spells/Human/Polymorph/PolyMorphDoneGround.glb`
- `Abilities/Spells/Human/Polymorph/PolyMorphTarget.glb`
- `Abilities/Spells/Human/Slow/SlowTarget.glb`
- `Abilities/Spells/Human/SpellSteal/SpellStealTarget.glb`
- `Abilities/Spells/Items/AIfb/AIfbSpecialArt.glb`
- `Abilities/Spells/Items/AIob/AIobSpecialArt.glb`
- `Abilities/Spells/Items/ClarityPotion/ClarityTarget.glb`
- `Abilities/Spells/Items/HealingSalve/HealingSalveTarget.glb`
- `Abilities/Spells/Items/OrbCorruption/OrbCorruptionMissile.glb`
- `Abilities/Spells/Items/OrbCorruption/OrbCorruptionSpecialArt.glb`
- `Abilities/Spells/Items/OrbVenom/OrbVenomSpecialArt.glb`
- `Abilities/Spells/Items/ResourceItems/ResourceEffectTarget.glb`
- `Abilities/Spells/Items/ScrollOfRegeneration/Scroll_Regen_Target.glb`
- `Abilities/Spells/Items/ScrollOfRejuvenation/ScrollManaHealth.glb`
- `Abilities/Spells/Items/StaffOfPurification/PurificationCaster.glb`
- `Abilities/Spells/Items/StaffOfPurification/PurificationTarget.glb`
- `Abilities/Spells/Items/StaffOfSanctuary/Staff_Sanctuary_Target.glb`
- `Abilities/Spells/Items/VampiricPotion/VampPotionCaster.glb`
- `Abilities/Spells/NightElf/Barkskin/BarkSkinTarget.glb`
- `Abilities/Spells/NightElf/CorrosiveBreath/ChimaeraAcidTargetArt.glb`
- `Abilities/Spells/NightElf/FaerieDragonInvis/FaerieDragon_Invis.glb`
- `Abilities/Spells/NightElf/Immolation/ImmolationDamage.glb`
- `Abilities/Spells/NightElf/MoonWell/MoonWellCasterArt.glb`
- `Abilities/Spells/NightElf/Rejuvenation/RejuvenationTarget.glb`
- `Abilities/Spells/NightElf/TargetArtLumber/TargetArtLumber.glb`
- `Abilities/Spells/Orc/Devour/DevourEffectArt.glb`
- `Abilities/Spells/Orc/Disenchant/DisenchantSpecialArt.glb`
- `Abilities/Spells/Orc/EtherealForm/SpiritWalkerChange.glb`
- `Abilities/Spells/Orc/LiquidFire/Liquidfire.glb`
- `Abilities/Spells/Orc/MirrorImage/MirrorImageDeathCaster.glb`
- `Abilities/Spells/Orc/Voodoo/VoodooAuraTarget.glb`
- `Abilities/Spells/Other/ANrl/ANrlTarget.glb`
- `Abilities/Spells/Other/ANrm/ANrmTarget.glb`
- `Abilities/Spells/Other/BreathOfFire/BreathOfFireDamage.glb`
- `Abilities/Spells/Other/BreathOfFire/BreathOfFireTarget.glb`
- `Abilities/Spells/Other/BreathOfFrost/BreathOfFrostTarget.glb`
- `Abilities/Spells/Other/Cleave/CleaveDamageTarget.glb`
- `Abilities/Spells/Other/CrushingWave/CrushingWaveDamage.glb`
- `Abilities/Spells/Other/Drain/DrainCaster.glb`
- `Abilities/Spells/Other/Drain/DrainTarget.glb`
- `Abilities/Spells/Other/Drain/ManaDrainCaster.glb`
- `Abilities/Spells/Other/Drain/ManaDrainTarget.glb`
- `Abilities/Spells/Other/FrostDamage/FrostDamage.glb`
- `Abilities/Spells/Other/ImmolationRed/ImmolationRedDamage.glb`
- `Abilities/Spells/Other/Monsoon/MonsoonRain.glb`
- `Abilities/Spells/Other/Silence/SilenceAreaBirth.glb`
- `Abilities/Spells/Other/Stampede/StampedeMissileDeath.glb`
- `Abilities/Spells/Other/StrongDrink/BrewmasterTarget.glb`
- `Abilities/Spells/Other/Tornado/TornadoSpinner.glb`
- `Abilities/Spells/Other/Tornado/Tornado_Target.glb`
- `Abilities/Spells/Undead/CarrionSwarm/CarrionSwarmDamage.glb`
- `Abilities/Spells/Undead/Cripple/CrippleTarget.glb`
- `Abilities/Spells/Undead/DarkRitual/DarkRitualCaster.glb`
- `Abilities/Spells/Undead/DeathandDecay/DeathandDecayDamage.glb`
- `Abilities/Spells/Undead/DeathandDecay/DeathandDecayTarget.glb`
- `Abilities/Spells/Undead/DeathPact/DeathPactCaster.glb`
- `Abilities/Spells/Undead/FrostArmor/FrostArmorDamage.glb`
- `Abilities/Spells/Undead/Impale/ImpaleCaster.glb`
- `Abilities/Spells/Undead/PlagueCloud/PlagueCloudCaster.glb`
- `Abilities/Spells/Undead/RegenerationAura/ObsidianRegenAura.glb`
- `Abilities/Spells/Undead/ReplenishHealth/ReplenishHealthCaster.glb`
- `Abilities/Spells/Undead/ReplenishMana/ReplenishManaCaster.glb`
- `Abilities/Spells/Undead/Unsummon/UnsummonTarget.glb`
- `Abilities/Weapons/AvengerMissile/AvengerMissile.glb`
- `Abilities/Weapons/BallistaMissile/BallistaImpact.glb`
- `Abilities/Weapons/BallistaMissile/BallistaMissileTarget.glb`
- `Abilities/Weapons/DragonHawkMissile/DragonHawkMissile.glb`
- `Abilities/Weapons/FlameThrowerMissile/FlameThrowerMissile.glb`
- `Abilities/Weapons/FrostWyrmMissile/FrostWyrmMissile.glb`
- `Abilities/Weapons/GlaiveMissile/GlaiveMissileTarget.glb`
- `Abilities/Weapons/GryphonRiderMissile/GryphonRiderMissileTarget.glb`
- `Abilities/Weapons/LocustMissile/LocustMissile.glb`
- `Abilities/Weapons/PhoenixMissile/Phoenix_Missile_mini.glb`
- `Abilities/Weapons/PoisonSting/PoisonStingTarget.glb`
- `Abilities/Weapons/SeaElementalMissile/SeaElementalMissile.glb`
- `Abilities/Weapons/SludgeMissile/SludgeMissile.glb`
- `Abilities/Weapons/SteamTank/SteamTankImpact.glb`
- `Abilities/Weapons/WaterElementalMissile/WaterElementalMissile.glb`
- `Abilities/Weapons/ZigguratFrostMissile/ZigguratFrostMissile.glb`
- `Environment/BlightDoodad/BlightDoodad.glb`
- `Environment/DNC/DNCAshenvale/DNCAshenValeTerrain/DNCAshenValeTerrain.glb`
- `Environment/DNC/DNCAshenvale/DNCAshenValeUnit/DNCAshenValeUnit.glb`
- `Environment/DNC/DNCDalaran/DNCDalaranTerrain/DNCDalaranTerrain.glb`
- `Environment/DNC/DNCDalaran/DNCDalaranUnit/DNCDalaranUnit.glb`
- `Environment/DNC/DNCDungeon/DNCDungeonTerrain/DNCDungeonTerrain.glb`
- `Environment/DNC/DNCDungeon/DNCDungeonUnit/DNCDungeonUnit.glb`
- `Environment/DNC/DNCFelwood/DNCFelWoodTerrain/DNCFelWoodTerrain.glb`
- `Environment/DNC/DNCFelwood/DNCFelWoodUnit/DNCFelWoodUnit.glb`
- `Environment/DNC/DNCLordaeron/DNCLordaeronTarget/DNCLordaeronTarget.glb`
- `Environment/DNC/DNCLordaeron/DNCLordaeronTerrain/DNCLordaeronTerrain.glb`
- `Environment/DNC/DNCLordaeron/DNCLordaeronUnit/DNCLordaeronUnit.glb`
- `Environment/DNC/DNCUnderground/DNCUndergroundTerrain/DNCUndergroundTerrain.glb`
- `Environment/DNC/DNCUnderground/DNCUndergroundUnit/DNCUndergroundUnit.glb`
- `Environment/LargeBuildingFire/LargeBuildingFire0.glb`
- `Environment/LargeBuildingFire/LargeBuildingFire1.glb`
- `Environment/LargeBuildingFire/LargeBuildingFire2.glb`
- `Environment/NightElfBuildingFire/ElfLargeBuildingFire0.glb`
- `Environment/NightElfBuildingFire/ElfLargeBuildingFire1.glb`
- `Environment/NightElfBuildingFire/ElfLargeBuildingFire2.glb`
- `Environment/NightElfBuildingFire/ElfSmallBuildingFire0.glb`
- `Environment/NightElfBuildingFire/ElfSmallBuildingFire1.glb`
- `Environment/NightElfBuildingFire/ElfSmallBuildingFire2.glb`
- `Environment/SmallBuildingFire/SmallBuildingFire0.glb`
- `Environment/SmallBuildingFire/SmallBuildingFire1.glb`
- `Environment/SmallBuildingFire/SmallBuildingFire2.glb`
- `Environment/UndeadBuildingFire/UndeadLargeBuildingFire0.glb`
- `Environment/UndeadBuildingFire/UndeadLargeBuildingFire1.glb`
- `Environment/UndeadBuildingFire/UndeadLargeBuildingFire2.glb`
- `Environment/UndeadBuildingFire/UndeadSmallBuildingFire0.glb`
- `Environment/UndeadBuildingFire/UndeadSmallBuildingFire1.glb`
- `Environment/UndeadBuildingFire/UndeadSmallBuildingFire2.glb`
- `File00000006.glb`
- `File00000011.glb`
- `File00000028.glb`
- `Objects/CinematicCameras/CameraCloseUpLow.glb`
- `Objects/CinematicCameras/CameraCloseUpLowNoise.glb`
- `Objects/CinematicCameras/CameraCloseUpMed.glb`
- `Objects/CinematicCameras/CameraCloseUpMedNoise.glb`
- `Objects/CinematicCameras/CameraJainaEnters.glb`
- `Objects/CinematicCameras/CameraPanLeftHigh.glb`
- `Objects/CinematicCameras/CameraPanLeftLow.glb`
- `Objects/CinematicCameras/CameraPanUpClose.glb`
- `Objects/CinematicCameras/CameraZoomInLow.glb`
- `Objects/CinematicCameras/CameraZoomInMid.glb`
- `Objects/CinematicCameras/CameraZoomOut.glb`
- `Objects/CinematicCameras/CameraZoomOutLow.glb`
- `Objects/CinematicCameras/CameraZoomOutMid.glb`
- `Objects/Spawnmodels/Critters/Albatross/CritterBloodAlbatross.glb`
- `Objects/Spawnmodels/Demon/DemonBlood/DemonBloodLarge0.glb`
- `Objects/Spawnmodels/Demon/DemonBlood/DemonBloodPitlord.glb`
- `Objects/Spawnmodels/Human/HCancelDeath/HCancelDeath.glb`
- `Objects/Spawnmodels/Human/HumanBlood/BloodElfSpellThiefBlood.glb`
- `Objects/Spawnmodels/Human/HumanBlood/HeroBloodElfBlood.glb`
- `Objects/Spawnmodels/Human/HumanBlood/HumanBloodFootman.glb`
- `Objects/Spawnmodels/Human/HumanBlood/HumanBloodKnight.glb`
- `Objects/Spawnmodels/Human/HumanBlood/HumanBloodLarge0.glb`
- `Objects/Spawnmodels/Human/HumanBlood/HumanBloodMortarTeam.glb`
- `Objects/Spawnmodels/Human/HumanBlood/HumanBloodPeasant.glb`
- `Objects/Spawnmodels/Human/HumanBlood/HumanBloodPriest.glb`
- `Objects/Spawnmodels/Human/HumanBlood/HumanBloodRifleman.glb`
- `Objects/Spawnmodels/Human/HumanBlood/HumanBloodSorceress.glb`
- `Objects/Spawnmodels/Naga/NagaBlood/NagaBloodWindserpent.glb`
- `Objects/Spawnmodels/Naga/NagaDeath/NagaDeath.glb`
- `Objects/Spawnmodels/NightElf/NightElfBlood/MALFurion_Blood.glb`
- `Objects/Spawnmodels/NightElf/NightElfBlood/NightElfBloodArcher.glb`
- `Objects/Spawnmodels/NightElf/NightElfBlood/NightElfBloodChimaera.glb`
- `Objects/Spawnmodels/NightElf/NightElfBlood/NightElfBloodDruidBear.glb`
- `Objects/Spawnmodels/NightElf/NightElfBlood/NightElfBloodDruidoftheClaw.glb`
- `Objects/Spawnmodels/NightElf/NightElfBlood/NightElfBloodDruidoftheTalon.glb`
- `Objects/Spawnmodels/NightElf/NightElfBlood/NightElfBloodDruidRaven.glb`
- `Objects/Spawnmodels/NightElf/NightElfBlood/NightElfBloodDryad.glb`
- `Objects/Spawnmodels/NightElf/NightElfBlood/NightElfBloodHeroDemonHunter.glb`
- `Objects/Spawnmodels/NightElf/NightElfBlood/NightElfBloodHeroKeeperoftheGrove.glb`
- `Objects/Spawnmodels/NightElf/NightElfBlood/NightElfBloodHippoGryph.glb`
- `Objects/Spawnmodels/NightElf/NightElfBlood/NightElfBloodHuntress.glb`
- `Objects/Spawnmodels/NightElf/NightElfBlood/NightElfBloodLarge0.glb`
- `Objects/Spawnmodels/NightElf/NightElfBlood/NightElfBloodLarge1.glb`
- `Objects/Spawnmodels/NightElf/NightElfBlood/NightElfBloodMoonPriestess.glb`
- `Objects/Spawnmodels/Orc/OrcBlood/BattrollBlood.glb`
- `Objects/Spawnmodels/Orc/OrcBlood/HeroShadowHunterBlood.glb`
- `Objects/Spawnmodels/Orc/OrcBlood/OrcBloodGrunt.glb`
- `Objects/Spawnmodels/Orc/OrcBlood/OrcBloodHeadhunter.glb`
- `Objects/Spawnmodels/Orc/OrcBlood/OrcBloodHellScream.glb`
- `Objects/Spawnmodels/Orc/OrcBlood/OrcBloodHeroFarSeer.glb`
- `Objects/Spawnmodels/Orc/OrcBlood/OrcBloodHeroTaurenChieftain.glb`
- `Objects/Spawnmodels/Orc/OrcBlood/OrcBloodKotoBeast.glb`
- `Objects/Spawnmodels/Orc/OrcBlood/OrcBloodLarge0.glb`
- `Objects/Spawnmodels/Orc/OrcBlood/OrcBloodPeon.glb`
- `Objects/Spawnmodels/Orc/OrcBlood/OrcBloodTauren.glb`
- `Objects/Spawnmodels/Orc/OrcBlood/OrcBloodWitchDoctor.glb`
- `Objects/Spawnmodels/Orc/OrcBlood/OrcBloodWolfrider.glb`
- `Objects/Spawnmodels/Orc/OrcBlood/OrdBloodRiderlessWyvernRider.glb`
- `Objects/Spawnmodels/Orc/OrcBlood/OrdBloodWyvernRider.glb`
- `Objects/Spawnmodels/Other/BeastmasterBlood/BeastmasterBlood.glb`
- `Objects/Spawnmodels/Other/HumanBloodCinematicEffect/HumanBloodCinematicEffect.glb`
- `Objects/Spawnmodels/Other/IllidanFootprint/IllidanWaterSpawnFootPrint.glb`
- `Objects/Spawnmodels/Other/NeutralBuildingExplosion/NeutralBuildingExplosion.glb`
- `Objects/Spawnmodels/Other/NPCBlood/NPCbloodVillagerWoman/NPCbloodVillagerWoman.glb`
- `Objects/Spawnmodels/Other/OrcBloodCinematicEffect/OrcBloodCinematicEffect.glb`
- `Objects/Spawnmodels/Other/PandarenBrewmasterBlood/PandarenBrewmasterBlood.glb`
- `Objects/Spawnmodels/Undead/ImpaleTargetDust/ImpaleTargetDust.glb`
- `Objects/Spawnmodels/Undead/UndeadBlood/UndeadBloodAbomination.glb`
- `Objects/Spawnmodels/Undead/UndeadBlood/UndeadBloodAcolyte.glb`
- `Objects/Spawnmodels/Undead/UndeadBlood/UndeadBloodCryptFiend.glb`
- `Objects/Spawnmodels/Undead/UndeadBlood/UndeadBloodGargoyle.glb`
- `Objects/Spawnmodels/Undead/UndeadBlood/UndeadBloodGhoul.glb`
- `Objects/Spawnmodels/Undead/UndeadBlood/UndeadBloodLarge0.glb`
- `Objects/Spawnmodels/Undead/UndeadBlood/UndeadBloodLarge1.glb`
- `Objects/Spawnmodels/Undead/UndeadBlood/UndeadBloodNecromancer.glb`
- `UI/Feedback/Autocast/UI-ModalButtonOn.glb`
- `UI/Feedback/QuestButton/UI-QuestButtonOn.glb`
