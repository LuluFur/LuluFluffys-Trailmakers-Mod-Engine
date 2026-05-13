---@meta
--------------------------------------------------------------------------------
-- Trailmakers Modding API -- Comprehensive LuaLS Reference
--
-- This file documents EVERY function, class, enum, and constant exposed by
-- the Trailmakers modding API.  It is intended as an IDE helper for
-- autocomplete / type-checking via LuaLS (lua-language-server).
--
-- Sources referenced throughout:
--   [DOCS]      trailmakers_docs.lua  (official API docs, shipped with game)
--   [SPAWN]     trailmakers_spawnables.txt  (578 spawnable prefab names)
--   [AUDIO]     trailmakers_audio.txt  (1,706 audio event names)
--   [WORKSHOP]  Steam Workshop content/585420/  (real-world mod usage)
--   [MOD]       mod/main.lua  (this project's discovered behaviors)
--
-- File path:
--   C:\Program Files (x86)\Steam\steamapps\common\Trailmakers\mods\trailmakers_docs.lua
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- 1. ENUMS & CONSTANTS
-- Source: [DOCS] trailmakers_docs.lua:5-35
--------------------------------------------------------------------------------

---@class ModApi
---@field os ModApiTmOs
---@field physics ModApiPhysics
---@field players ModApiPlayers
---@field playerUI ModApiPlayerUI
---@field audio ModApiAudio
---@field input ModApiInput
---@field world ModApiWorld
---@field vector3 ModVector3Constructor
---@field quaternion ModQuaternionConstructor
---@field color ModColorConstructor
---@field enums ModApiEnums
---@field UICallbackData UICallbackData
tm = {}

---Table of Enum types
-- Source: [DOCS]:5-35
---@class ModApiEnums
---@field respawnReason ModRespawnReason
---@field damageType ModDamageType
tm.enums = {}

---@enum ModRespawnReason
-- Source: [DOCS]:9-16
tm.enums.respawnReason = {
    death = "DEATH",
    respawn = "RESPAWN",
    killed = "KILLED",
    ejectedFromSeat = "EJECTEDFROMSEAT",
    teleport = "TELEPORT",
}

---@enum ModDamageType
-- Source: [DOCS]:18-35
tm.enums.damageType = {
    generic = "Generic",
    impact = "Impact",
    explosion = "Explosion",
    lava = "Lava",
    projectile = "Projectile",
    electric = "Electric",
    jointTear = "JointTear",
    exitSeat = "ExitSeat",
    emp = "Emp",
    spaceBlaster = "SpaceBlaster",
    mechanicalFailure = "MechanicalFailure",
    harvestBasic = "HarvestBasic",
    harvestMineral = "HarvestMineral",
    harvestMineralTwo = "HarvestMineral2",
    harvestOrganic = "HarvestOrganic",
}


--------------------------------------------------------------------------------
-- 2. tm.os -- System & File I/O
-- Source: [DOCS]:37-101
--------------------------------------------------------------------------------

---OS-level functionality
---@class ModApiTmOs
tm.os = {}

---Higher-level function to load and run chunk of code from specified filename.
---Equivalent to the native 'dofile' function in Lua.
-- Source: [DOCS]:42-44
---@param filename string
---@return any
function tm.os.DoFile(filename) end

---Read all text of a file in the mod's static data directory.
---Files in the static data directory can only be read and NOT written to.
-- Source: [DOCS]:47-50
---@param path string
---@return string
function tm.os.ReadAllText_Static(path) end

---Read all text of a file in the mod's dynamic data directory.
---Files in the dynamic data directory can be both read and written to.
---The dynamic data directory will NOT be uploaded to the Steam Workshop.
---
---QUIRK: Returns "" (empty string) for files that don't exist or were never
---written by the mod -- does NOT return nil.
-- Source: [DOCS]:53-57, [MOD] discovered behavior
---@param path string
---@return string
function tm.os.ReadAllText_Dynamic(path) end

---Create or overwrite a file in the mod's dynamic data directory.
---Files in the dynamic data directory can be both read and written to.
---The dynamic data directory will NOT be uploaded to the Steam Workshop.
---
---QUIRK: Rejects empty strings -- always use " " (a single space) when you
---need to clear/reset a file.
-- Source: [DOCS]:59-64, [MOD] discovered behavior
---@param path string
---@param stringToWrite string
---@return nil
function tm.os.WriteAllText_Dynamic(path, stringToWrite) end

---Emit a log message.
---Output goes to: <game>/mods/<ModName>.log
-- Source: [DOCS]:67-69
---@param message string
---@return nil
function tm.os.Log(message) end

---Get time game has been playing in seconds.
---Equivalent to 'UnityEngine.Time.time'.
-- Source: [DOCS]:72-74
---@return number
function tm.os.GetTime() end

---Get the time since the game has started in seconds.
---Equivalent to 'UnityEngine.Time.realtimeSinceStartup'.
-- Source: [DOCS]:77-80
---@return number
function tm.os.GetRealtimeSinceStartup() end

---Get the time since last update.
-- Source: [DOCS]:83-85
---@return number
function tm.os.GetModDeltaTime() end

---Determines how often the mod gets updated.
---"1/60" means 60 times per second. Can't update faster than the game.
-- Source: [DOCS]:88-91
---@param targetDeltaTime number
---@return nil
function tm.os.SetModTargetDeltaTime(targetDeltaTime) end

---Returns the target delta time for the mod.
-- Source: [DOCS]:94-96
---@return number
function tm.os.GetModTargetDeltaTime() end

---Returns true if session is in singleplayer.
-- Source: [DOCS]:99-101
---@return boolean
function tm.os.IsSingleplayer() end


--------------------------------------------------------------------------------
-- 3. tm.physics -- Spawning, Physics, Raycasting
-- Source: [DOCS]:103-279
--------------------------------------------------------------------------------

---Environment, Physics, Time, Assets and Objects.
---@class ModApiPhysics
tm.physics = {}

---Set the physics timescale.
-- Source: [DOCS]:108-111
---@param speed number
---@return nil
function tm.physics.SetTimeScale(speed) end

---Get the physics timescale.
-- Source: [DOCS]:114-116
---@return number
function tm.physics.GetTimeScale() end

---Remove the physics timescale (reset to default).
-- Source: [DOCS]:179-181
---@return nil
function tm.physics.RemoveTimeScale() end

---Deprecated: Set the physics gravity in the down direction.
-- Source: [DOCS]:119-122
---@deprecated Use SetGravityMultiplier instead
---@param strength number
---@return nil
function tm.physics.SetGravity(strength) end

---Set the gravity multiplier. Has no effect in zero G locations.
---For example, setting the multiplier to 2 doubles gravity.
-- Source: [DOCS]:125-128
---@param multiplier number
---@return nil
function tm.physics.SetGravityMultiplier(multiplier) end

---Deprecated: Set the physics gravity as per the provided vector.
-- Source: [DOCS]:131-134
---@deprecated Use SetGravityMultiplier instead
---@param gravity ModVector3
---@return nil
function tm.physics.SetGravity(gravity) end

---Deprecated: Get the physics gravity.
-- Source: [DOCS]:137-139
---@deprecated
---@return ModVector3
function tm.physics.GetGravity() end

---Get the gravity multiplier.
-- Source: [DOCS]:142-144
---@return number
function tm.physics.GetGravityMultiplier() end

---Spawn a spawnable at the position, e.g. "PFB_Barrel".
---Returns a ModGameObject that can be manipulated.
---
---USAGE PATTERN (Source: [WORKSHOP] mods 2993133188, 3304407501):
---  local obj = tm.physics.SpawnObject(pos, "PFB_Barrel")
---  obj.GetTransform().SetRotation(0, 90, 0)
---  obj.GetTransform().SetScale(1.00001, 2, 2)  -- avoid exactly 1.0 on X
---  obj.SetIsStatic(true)
---  obj.SetIsVisible(true)
---  obj.SetIsTrigger(false)
---
---QUIRK: Scale of exactly 1.0 on the X axis may cause physics issues.
---Use 1.00001 instead.
-- Source: [DOCS]:147-151, [WORKSHOP] mod 3304407501:127-129
---@param position ModVector3
---@param name string
---@return ModGameObject
function tm.physics.SpawnObject(position, name) end

---Despawn all spawned objects from this mod.
-- Source: [DOCS]:154-156
---@return nil
function tm.physics.ClearAllSpawns() end

---Despawn a specific spawnable.
-- Source: [DOCS]:159-162
---@param gameObject ModGameObject
---@return nil
function tm.physics.DespawnObject(gameObject) end

---Get a list of all possible spawnable names.
---Returns 578 prefab names (see Section 13 for full list).
-- Source: [DOCS]:165-167, [SPAWN]
---@return string[]
function tm.physics.SpawnableNames() end

---Returns all block metadata.
-- Source: [DOCS]:174-177
---@return ModBlockMetaData[]
function tm.physics.GetAllBlockMetaData() end

---Add a mesh to all clients.
---Note: this will have to be sent to the client when they join.
-- Source: [DOCS]:184-188
---@param filename string
---@param resourceName string
---@return nil
function tm.physics.AddMesh(filename, resourceName) end

---Add a texture to all clients.
---Note: this will have to be sent to the client when they join.
-- Source: [DOCS]:191-195
---@param filename string
---@param resourceName string
---@return nil
function tm.physics.AddTexture(filename, resourceName) end

---Spawn a custom object where mesh and texture have been set by AddMesh/AddTexture.
-- Source: [DOCS]:209-213
---@param position ModVector3
---@param meshName string
---@param textureName string
---@return ModGameObject
function tm.physics.SpawnCustomObject(position, meshName, textureName) end

---Spawn a custom physics object where mesh and texture have been set by AddMesh/AddTexture.
-- Source: [DOCS]:199-205
---@param position ModVector3
---@param meshName string
---@param textureName string
---@param isKinematic boolean
---@param mass number
---@return ModGameObject
function tm.physics.SpawnCustomObjectRigidbody(position, meshName, textureName, isKinematic, mass) end

---Same as SpawnCustomObject BUT adds concave collision support.
-- Source: [DOCS]:216-221
---@param position ModVector3
---@param meshName string
---@param textureName string
---@return ModGameObject
function tm.physics.SpawnCustomObjectConcave(position, meshName, textureName) end

---Spawn a box trigger that will detect overlap but will not interact with physics.
-- Source: [DOCS]:224-228
---@param position ModVector3
---@param size ModVector3
---@return ModGameObject
function tm.physics.SpawnBoxTrigger(position, size) end

---Sets the build complexity value. Default value is 700.
---Values above 700 can make the game unstable.
-- Source: [DOCS]:231-234
---@param value number
---@return nil
function tm.physics.SetBuildComplexity(value) end

---Registers a function to the collision enter callback of a game object.
---
---QUIRK: functionName must be a string name of a global function, not a
---function reference. Store the function in _G.
-- Source: [DOCS]:237-241, [WORKSHOP] trackmakermod
---@param targetObject ModGameObject
---@param functionName string
---@return function
function tm.physics.RegisterFunctionToCollisionEnterCallback(targetObject, functionName) end

---Registers a function to the collision exit callback of a game object.
---
---QUIRK: functionName must be a string name of a global function, not a
---function reference. Store the function in _G.
-- Source: [DOCS]:244-248, [WORKSHOP] trackmakermod
---@param targetObject ModGameObject
---@param functionName string
---@return function
function tm.physics.RegisterFunctionToCollisionExitCallback(targetObject, functionName) end

---Returns a bool if raycast hit something. Arguments get overwritten with raycast data.
-- Source: [DOCS]:251-258
---@param origin ModVector3
---@param direction ModVector3
---@param hitPositionOut ModVector3
---@param maxDistance number
---@param ignoreTriggers boolean
---@return boolean
function tm.physics.Raycast(origin, direction, hitPositionOut, maxDistance, ignoreTriggers) end

---Returns a ModRaycastHit with full hit information.
-- Source: [DOCS]:261-267
---@param origin ModVector3
---@param direction ModVector3
---@param maxDistance number
---@param ignoreTriggers boolean
---@return ModRaycastHit
function tm.physics.RaycastData(origin, direction, maxDistance, ignoreTriggers) end

---Returns the internal name for the current map.
-- Source: [DOCS]:270-272
---@return string
function tm.physics.GetMapName() end

---Deprecated: Returns the wind velocity at a position.
---Use tm.world.GetWindVelocityAtPosition instead.
-- Source: [DOCS]:275-279
---@deprecated Use tm.world.GetWindVelocityAtPosition instead
---@param position ModVector3
---@return ModVector3
function tm.physics.GetWindVelocityAtPosition(position) end


--------------------------------------------------------------------------------
-- 4. tm.players -- Player Management
-- Source: [DOCS]:281-636
--------------------------------------------------------------------------------

---Represents in-game player management.
---@class ModApiPlayers
---@field OnPlayerJoined OnPlayerJoinedEvent
---@field OnPlayerLeft OnPlayerLeftEvent
---@field OnPlayerDied OnPlayerDiedEvent
---@field OnPlayerSpawned OnPlayerSpawnedEvent
---@field OnPlayerEnterSeat OnPlayerEnterSeatEvent
---@field OnPlayerExitSeat OnPlayerExitSeatEvent
---@field OnPlayerFlipStructure OnPlayerFlipStructureEvent
---@field OnPlayerRepairStructure OnPlayerRepairStructureEvent
---@field OnPlayerKilledPlayer OnPlayerKilledPlayerEvent
---@field OnPlayerTeamChanged OnPlayerTeamChangedEvent
---@field OnPlayerEnterBuilder OnPlayerEnterBuilderEvent
---@field OnPlayerExitBuilder OnPlayerExitBuilderEvent
tm.players = {}

-- -- Player Events --

---Event triggered when a player joins the server.
-- Source: [DOCS]:283-287
---@class OnPlayerJoinedEvent
---@field add fun(callback: fun(player: ModPlayer)): nil
---@field remove fun(callback: fun(player: ModPlayer)): nil
tm.players.OnPlayerJoined = {}

---Event triggered when a player leaves the server.
-- Source: [DOCS]:289-293
---@class OnPlayerLeftEvent
---@field add fun(callback: fun(player: ModPlayer)): nil
---@field remove fun(callback: fun(player: ModPlayer)): nil
tm.players.OnPlayerLeft = {}

---Event triggered when a player dies.
-- Source: [DOCS]:295-299
---@class OnPlayerDiedEvent
---@field add fun(callback: fun(player: ModPlayer, damage: ModDamage)): nil
---@field remove fun(callback: fun(player: ModPlayer, damage: ModDamage)): nil
tm.players.OnPlayerDied = {}

---Event triggered when a player spawns.
-- Source: [DOCS]:313-317
---@class OnPlayerSpawnedEvent
---@field add fun(callback: fun(player: ModPlayer, respawnReason: ModRespawnReason)): nil
---@field remove fun(callback: fun(player: ModPlayer, respawnReason: ModRespawnReason)): nil
tm.players.OnPlayerSpawned = {}

---Event triggered when a player enters a seat/structure.
-- Source: [DOCS]:307-311
---@class OnPlayerEnterSeatEvent
---@field add fun(callback: fun(player: ModPlayer)): nil
---@field remove fun(callback: fun(player: ModPlayer)): nil
tm.players.OnPlayerEnterSeat = {}

---Event triggered when a player exits a seat/structure.
-- Source: [DOCS]:301-305
---@class OnPlayerExitSeatEvent
---@field add fun(callback: fun(player: ModPlayer)): nil
---@field remove fun(callback: fun(player: ModPlayer)): nil
tm.players.OnPlayerExitSeat = {}

---Event triggered when a player flips a structure.
-- Source: [DOCS]:319-323
---@class OnPlayerFlipStructureEvent
---@field add fun(callback: fun(player: ModPlayer, structure: ModStructure)): nil
---@field remove fun(callback: fun(player: ModPlayer, structure: ModStructure)): nil
tm.players.OnPlayerFlipStructure = {}

---Event triggered when a player repairs a structure.
-- Source: [DOCS]:325-329
---@class OnPlayerRepairStructureEvent
---@field add fun(callback: fun(player: ModPlayer, structure: ModStructure)): nil
---@field remove fun(callback: fun(player: ModPlayer, structure: ModStructure)): nil
tm.players.OnPlayerRepairStructure = {}

---Event triggered when a player kills another player.
-- Source: [DOCS]:331-335
---@class OnPlayerKilledPlayerEvent
---@field add fun(callback: fun(player: ModPlayer, damage: ModDamage, killedPlayer: ModPlayer)): nil
---@field remove fun(callback: fun(player: ModPlayer, damage: ModDamage, killedPlayer: ModPlayer)): nil
tm.players.OnPlayerKilledPlayer = {}

---Event triggered when a player changes to another team.
-- Source: [DOCS]:337-341
---@class OnPlayerTeamChangedEvent
---@field add fun(callback: fun(player: ModPlayer, newTeamId: number)): nil
---@field remove fun(callback: fun(player: ModPlayer, newTeamId: number)): nil
tm.players.OnPlayerTeamChanged = {}

---Event triggered when a player enters the builder.
-- Source: [DOCS]:343-347
---@class OnPlayerEnterBuilderEvent
---@field add fun(callback: fun(player: ModPlayer)): nil
---@field remove fun(callback: fun(player: ModPlayer)): nil
tm.players.OnPlayerEnterBuilder = {}

---Event triggered when a player exits the builder.
-- Source: [DOCS]:349-353
---@class OnPlayerExitBuilderEvent
---@field add fun(callback: fun(player: ModPlayer)): nil
---@field remove fun(callback: fun(player: ModPlayer)): nil
tm.players.OnPlayerExitBuilder = {}

-- -- Player Query Functions --

---Get all players currently connected to the server.
-- Source: [DOCS]:357-359
---@return ModPlayer[]
function tm.players.CurrentPlayers() end

---Get the player's name.
-- Source: [DOCS]:460-463
---@param playerId number
---@return string
function tm.players.GetPlayerName(playerId) end

---Get the player's team index.
-- Source: [DOCS]:466-469
---@param playerId number
---@return number
function tm.players.GetPlayerTeam(playerId) end

---Set the player's team index.
-- Source: [DOCS]:472-476
---@param playerId number
---@param teamID number
---@return nil
function tm.players.SetPlayerTeam(playerId, teamID) end

---Returns the highest team index allowed.
-- Source: [DOCS]:479-481
---@return number
function tm.players.GetMaxTeamIndex() end

---Get the transform of a player.
-- Source: [DOCS]:380-383
---@param playerId number
---@return ModTransform
function tm.players.GetPlayerTransform(playerId) end

---Get the GameObject of a player.
-- Source: [DOCS]:386-389
---@param playerId number
---@return ModGameObject
function tm.players.GetPlayerGameObject(playerId) end

---Get player's unique profile id.
-- Source: [DOCS]:374-377
---@param playerId number
---@return string
function tm.players.GetPlayerProfileId(playerId) end

---Is player administrator.
-- Source: [DOCS]:368-371
---@param playerId number
---@return boolean
function tm.players.IsPlayerAdministrator(playerId) end

---Returns true if the player is in a seat.
-- Source: [DOCS]:392-395
---@param playerId number
---@return boolean
function tm.players.IsPlayerInSeat(playerId) end

---Forces a player to exit their seat.
-- Source: [DOCS]:398-401
---@param playerId number
---@return nil
function tm.players.ForceExitSeat(playerId) end

---Returns ModStructure of the seat the player is in, or null if not in a seat.
-- Source: [DOCS]:404-407
---@param playerId number
---@return ModStructure|nil
function tm.players.OccupiedStructure(playerId) end

---Get all structure(s) owned by that player.
-- Source: [DOCS]:436-439
---@param playerId number
---@return ModStructure[]
function tm.players.GetPlayerStructures(playerId) end

---Get structure by Id.
-- Source: [DOCS]:442-445
---@param structureId string
---@return ModStructure[]
function tm.players.GetSpawnedStructureById(structureId) end

---Get the structure(s) currently in build mode for a player.
-- Source: [DOCS]:448-451
---@param playerId number
---@return ModStructure[]
function tm.players.GetPlayerStructuresInBuild(playerId) end

---Get the last selected block in the builder for that player.
---Returns nil if the player hasn't selected a block in the current session.
---Dragging blocks doesn't count as selecting them.
---When multiple blocks are selected, only the first selected block is returned.
-- Source: [DOCS]:454-457
---@param playerId number
---@return ModBlock|nil
function tm.players.GetPlayerSelectBlockInBuild(playerId) end

---Returns the block the player is seated in.
-- Source: [DOCS]:589-592
---@param playerId number
---@return ModBlock
function tm.players.GetPlayerSeatBlock(playerId) end

---Returns true if the player is in build mode.
-- Source: [DOCS]:484-488
---@param playerId number
---@return boolean
function tm.players.GetPlayerIsInBuildMode(playerId) end

---Checks if building is enabled for a player.
-- Source: [DOCS]:577-580
---@param playerId number
---@return boolean
function tm.players.GetBuilderEnabled(playerId) end

---Checks if repairing is enabled for a player.
-- Source: [DOCS]:583-586
---@param playerId number
---@return boolean
function tm.players.GetRepairEnabled(playerId) end

---Gets the primary block color of a player.
-- Source: [DOCS]:626-629
---@param playerId number
---@return ModColor
function tm.players.GetPrimaryBlockColor(playerId) end

---Gets the secondary block color of a player.
-- Source: [DOCS]:632-635
---@param playerId number
---@return ModColor
function tm.players.GetSecondaryBlockColor(playerId) end

-- -- Player Control Functions --

---Kills a player.
-- Source: [DOCS]:410-413
---@param playerId number
---@return nil
function tm.players.KillPlayer(playerId) end

---Checks if player can be killed.
-- Source: [DOCS]:416-419
---@param playerId number
---@return boolean
function tm.players.CanKillPlayer(playerId) end

---Sets the invincibility status of a player.
-- Source: [DOCS]:422-426
---@param playerId number
---@param enabled boolean
---@return nil
function tm.players.SetPlayerIsInvincible(playerId, enabled) end

---Enables and disables the jetpack.
-- Source: [DOCS]:429-433
---@param playerId number
---@param enabled boolean
---@return nil
function tm.players.SetJetpackEnabled(playerId, enabled) end

---Forcefully disconnect a given player.
-- Source: [DOCS]:362-365
---@param playerId number
---@return nil
function tm.players.Kick(playerId) end

---Set if the builder for a player should be enabled.
-- Source: [DOCS]:564-568
---@param playerId number
---@param isEnabled boolean
---@return nil
function tm.players.SetBuilderEnabled(playerId, isEnabled) end

---Set if repairing for a player should be enabled.
---Also enables/disables transform.
-- Source: [DOCS]:570-574
---@param playerId number
---@param isEnabled boolean
---@return nil
function tm.players.SetRepairEnabled(playerId, isEnabled) end

---Set block limit for a specific block type. 0 means the block will be banned.
-- Source: [DOCS]:491-494
---@param blockTypeGuid string
---@param limit number
---@return nil
function tm.players.SetBlockLimit(blockTypeGuid, limit) end

-- -- Structure Functions --

---Spawn a structure for a player with given blueprint, position and rotation.
-- Source: [DOCS]:540-547
---@param playerId number
---@param blueprint string
---@param structureId string
---@param position ModVector3
---@param rotation ModVector3
---@return nil
function tm.players.SpawnStructure(playerId, blueprint, structureId, position, rotation) end

---Despawn a structure.
-- Source: [DOCS]:550-553
---@param structureId string
---@return nil
function tm.players.DespawnStructure(structureId) end

---Places the player in the seat of a structure.
-- Source: [DOCS]:556-560
---@param playerId number
---@param structureId string
---@return nil
function tm.players.PlacePlayerInSeat(playerId, structureId) end

-- -- Camera Functions (max 1 per player) --

---Add a camera. THERE CAN ONLY BE 1 CAMERA PER PLAYER!
-- Source: [DOCS]:497-503
---@param playerId number
---@param position ModVector3
---@param rotation ModVector3
---@param priority number
---@return nil
function tm.players.AddCamera(playerId, position, rotation, priority) end

---Remove a camera. THERE CAN ONLY BE 1 CAMERA PER PLAYER!
-- Source: [DOCS]:506-509
---@param playerId number
---@return nil
function tm.players.RemoveCamera(playerId) end

---Set camera position.
-- Source: [DOCS]:512-515
---@param playerId number
---@param position ModVector3
---@return nil
function tm.players.SetCameraPosition(playerId, position) end

---Set camera rotation.
-- Source: [DOCS]:518-521
---@param playerId number
---@param rotation ModVector3
---@return nil
function tm.players.SetCameraRotation(playerId, rotation) end

---Activate a camera with fade-in.
-- Source: [DOCS]:524-528
---@param playerId number
---@param fadeInDuration number
---@return nil
function tm.players.ActivateCamera(playerId, fadeInDuration) end

---Deactivate a camera with fade-out.
-- Source: [DOCS]:531-535
---@param playerId number
---@param fadeOutDuration number
---@return nil
function tm.players.DeactivateCamera(playerId, fadeOutDuration) end

-- -- Spawn Point Functions (max 8 players) --

---Sets the spawn location the player should use when respawning.
---Will be overwritten if another spawn location is set, e.g. checkpoints on the map.
-- Source: [DOCS]:595-599
---@param playerId number
---@param spawnLocationId string
---@return nil
function tm.players.SetPlayerSpawnLocation(playerId, spawnLocationId) end

---Sets the position and rotation of the spawn point for a player ID at a given
---spawn location. Each spawn location is a group of spawn points, one for each
---player ID.
-- Source: [DOCS]:602-608
---@param playerIndex number
---@param spawnLocationId string
---@param position ModVector3
---@param rotation ModVector3
---@return nil
function tm.players.SetSpawnPoint(playerIndex, spawnLocationId, position, rotation) end

---Teleports a player to the selected spawn point.
---Set keepStructure to true and it will try to keep the structure when teleporting.
-- Source: [DOCS]:611-616
---@param playerId number
---@param spawnPointId string
---@param keepStructure boolean
---@return nil
function tm.players.TeleportPlayerToSpawnPoint(playerId, spawnPointId, keepStructure) end

---Teleports ALL players to the selected spawn point.
---Use this to move up to 8 players to their spawn position.
---Set keepStructure to true and it will try to keep the structure when teleporting.
-- Source: [DOCS]:619-623
---@param spawnPointId string
---@param keepStructure boolean
---@return nil
function tm.players.TeleportAllPlayersToSpawnPoint(spawnPointId, keepStructure) end


--------------------------------------------------------------------------------
-- 5. tm.playerUI -- Chat, UI, Messages
-- Source: [DOCS]:638-805
--------------------------------------------------------------------------------

---UI Window.
---@class ModApiPlayerUI
---@field OnChatMessage OnChatMessageEvent
tm.playerUI = {}

-- -- Chat --

---Event triggered when a player sends a chat message.
---
---QUIRK: SendChatMessage echoes back through OnChatMessage on the next frame.
---Use echo suppression (count map with TTL) to avoid infinite loops.
-- Source: [DOCS]:640-644, [MOD] echo suppression system
---@class OnChatMessageEvent
---@field add fun(callback: fun(senderName: string, message: string, color: ModColor)): nil
---@field remove fun(callback: fun(senderName: string, message: string, color: ModColor)): nil
tm.playerUI.OnChatMessage = {}

---Send a message to chat. The message will be sent to all players in the game.
---QUIRK: Ignored in singleplayer.
-- Source: [DOCS]:648-653
---@param senderName string
---@param message string
---@param color? ModColor @ Optional color parameter
---@return nil
function tm.playerUI.SendChatMessage(senderName, message, color) end

-- -- Mod UI --

---Add a button to the client's mod UI.
-- Source: [DOCS]:656-663
---@param playerId number
---@param id string
---@param defaultValue string
---@param callback function
---@param data any
---@return nil
function tm.playerUI.AddUIButton(playerId, id, defaultValue, callback, data) end

---Add a text field to the client's mod UI.
-- Source: [DOCS]:666-673
---@param playerId number
---@param id string
---@param defaultValue string
---@param callback function
---@param data any
---@return nil
function tm.playerUI.AddUIText(playerId, id, defaultValue, callback, data) end

---Add a label to the client's mod UI.
-- Source: [DOCS]:676-681
---@param playerId number
---@param id string
---@param defaultValue string
---@return nil
function tm.playerUI.AddUILabel(playerId, id, defaultValue) end

---Remove a UI element.
-- Source: [DOCS]:684-688
---@param playerId number
---@param id string
---@return nil
function tm.playerUI.RemoveUI(playerId, id) end

---Set the value of a client's UI element.
-- Source: [DOCS]:691-696
---@param playerId number
---@param id string
---@param value string
---@return nil
function tm.playerUI.SetUIValue(playerId, id, value) end

---Remove all UI elements for that player.
-- Source: [DOCS]:699-702
---@param playerId number
---@return nil
function tm.playerUI.ClearUI(playerId) end

-- -- Subtle Messages (max 32 characters) --

---Adds a subtle message for a specific player.
---Optional duration and path to custom sprite icon.
---String limits: 32 characters.
-- Source: [DOCS]:705-712
---@param playerId number
---@param header string
---@param message string
---@param duration? number
---@param spriteAssetName? string
---@return string @ Message ID for later removal/update
function tm.playerUI.AddSubtleMessageForPlayer(playerId, header, message, duration, spriteAssetName) end

---Adds a subtle message for ALL players.
---Optional duration and path to custom sprite icon.
---String limits: 32 characters.
-- Source: [DOCS]:715-721
---@param header string
---@param message string
---@param duration? number
---@param spriteAssetName? string
---@return string @ Message ID for later removal/update
function tm.playerUI.AddSubtleMessageForAllPlayers(header, message, duration, spriteAssetName) end

---Removes a subtle message for a player.
-- Source: [DOCS]:741-745
---@param playerId number
---@param id string
---@return nil
function tm.playerUI.RemoveSubtleMessageForPlayer(playerId, id) end

---Removes a subtle message for ALL players.
-- Source: [DOCS]:748-751
---@param id string
---@return nil
function tm.playerUI.RemoveSubtleMessageForAll(id) end

---Update the header of a subtle message for a player.
-- Source: [DOCS]:754-759
---@param playerId number
---@param id string
---@param newHeader string
---@return nil
function tm.playerUI.SubtleMessageUpdateHeaderForPlayer(playerId, id, newHeader) end

---Update the header of a subtle message for all players.
-- Source: [DOCS]:762-766
---@param id string
---@param newHeader string
---@return nil
function tm.playerUI.SubtleMessageUpdateHeaderForAll(id, newHeader) end

---Update the message of a subtle message for a player.
-- Source: [DOCS]:769-774
---@param playerId number
---@param id string
---@param newMessage string
---@return nil
function tm.playerUI.SubtleMessageUpdateMessageForPlayer(playerId, id, newMessage) end

---Update the message of a subtle message for ALL players.
-- Source: [DOCS]:777-781
---@param id string
---@param newMessage string
---@return nil
function tm.playerUI.SubtleMessageUpdateMessageForAll(id, newMessage) end

-- -- Intrusive Messages (default 3s) --

---Shows an intrusive message for a specific player.
---Optional duration of the message can be added, default is 3 seconds.
-- Source: [DOCS]:724-730
---@param playerId number
---@param header string
---@param message string
---@param duration? number
---@return nil
function tm.playerUI.ShowIntrusiveMessageForPlayer(playerId, header, message, duration) end

---Shows an intrusive message for ALL players.
---Optional duration of the message can be added, default is 3 seconds.
-- Source: [DOCS]:733-738
---@param header string
---@param message string
---@param duration? number
---@return nil
function tm.playerUI.ShowIntrusiveMessageForAllPlayers(header, message, duration) end

-- -- Mouse --

---Registers a function callback to get the world position of the cursor
---when left mouse button is clicked.
-- Source: [DOCS]:784-789
---@param playerId number
---@param callback function
---@return function
function tm.playerUI.RegisterMouseDownPositionCallback(playerId, callback) end

---Deregisters a function callback for mouse down position.
-- Source: [DOCS]:792-796
---@param playerId number
---@param callback function
---@return function
function tm.playerUI.DeregisterMouseDownPositionCallback(playerId, callback) end

---Show cursor world position in the UI.
-- Source: [DOCS]:799-801
---@return nil
function tm.playerUI.ShowCursorWorldPosition() end

---Hide cursor world position in the UI.
-- Source: [DOCS]:803-805
---@return nil
function tm.playerUI.HideCursorWorldPosition() end


--------------------------------------------------------------------------------
-- 6. tm.audio
-- Source: [DOCS]:808-835
-- Note: 1,706 audio events available (Source: [AUDIO])
--------------------------------------------------------------------------------

---Audio played in-game world.
---@class ModApiAudio
tm.audio = {}

---Play audio at a position. This is more cost-friendly but you cannot stop
---or move the sound.
-- Source: [DOCS]:812-817
---@param audioName string
---@param position ModVector3
---@param keepObjectDuration number
---@return nil
function tm.audio.PlayAudioAtPosition(audioName, position, keepObjectDuration) end

---Play audio on a GameObject.
-- Source: [DOCS]:820-824
---@param audioName string
---@param modGameObject ModGameObject
---@return nil
function tm.audio.PlayAudioAtGameobject(audioName, modGameObject) end

---Stop all audio on a GameObject.
-- Source: [DOCS]:827-830
---@param modGameObject ModGameObject
---@return nil
function tm.audio.StopAllAudioAtGameobject(modGameObject) end

---Returns a list of all playable audio names.
---Returns 1,706 audio event names (see Section 14 for categories).
-- Source: [DOCS]:833-835, [AUDIO]
---@return string[]
function tm.audio.GetAudioNames() end


--------------------------------------------------------------------------------
-- 7. tm.input
-- Source: [DOCS]:838-867
--------------------------------------------------------------------------------

---Input interaction from players.
---@class ModApiInput
---@field OnPlayerKeyDown OnPlayerKeyDownEvent
---@field OnPlayerKeyUp OnPlayerKeyUpEvent
tm.input = {}

---Event triggered when a player presses a key.
-- Source: [DOCS]:840-844
---@class OnPlayerKeyDownEvent
---@field add fun(callback: fun(player: ModPlayer, keyName: string)): nil
---@field remove fun(callback: fun(player: ModPlayer, keyName: string)): nil
tm.input.OnPlayerKeyDown = {}

---Event triggered when a player releases a key.
-- Source: [DOCS]:846-850
---@class OnPlayerKeyUpEvent
---@field add fun(callback: fun(player: ModPlayer, keyName: string)): nil
---@field remove fun(callback: fun(player: ModPlayer, keyName: string)): nil
tm.input.OnPlayerKeyUp = {}

---Registers a function to the callback of when the given player presses the given key.
---
---QUIRK: functionName must be a string name of a global function, not a
---function reference. Store the function in _G table.
-- Source: [DOCS]:854-859, [MOD], [DOCS] pattern
---@param playerId number
---@param functionName string
---@param keyName string
---@return function
function tm.input.RegisterFunctionToKeyDownCallback(playerId, functionName, keyName) end

---Registers a function to the callback of when the given player releases the given key.
---
---QUIRK: functionName must be a string name of a global function, not a
---function reference. Store the function in _G table.
-- Source: [DOCS]:862-867, [MOD], [DOCS] pattern
---@param playerId number
---@param functionName string
---@param keyName string
---@return function
function tm.input.RegisterFunctionToKeyUpCallback(playerId, functionName, keyName) end


--------------------------------------------------------------------------------
-- 8. tm.world
-- Source: [DOCS]:1314-1356
--------------------------------------------------------------------------------

---Represents the current world.
---@class ModApiWorld
tm.world = {}

---Set time of day. (0-100). No effect if time is paused.
-- Source: [DOCS]:1330-1333
---@param percentage number
---@return nil
function tm.world.SetTimeOfDay(percentage) end

---Get time of day. (0-100).
-- Source: [DOCS]:1336-1338
---@return number
function tm.world.GetTimeOfDay() end

---Set if time of day should be paused or not.
-- Source: [DOCS]:1341-1344
---@param isPaused boolean
---@return nil
function tm.world.SetPausedTimeOfDay(isPaused) end

---Returns if the time of day is currently paused.
-- Source: [DOCS]:1353-1355
---@return boolean
function tm.world.IsTimeOfDayPaused() end

---Set the cycle duration (seconds how fast a day goes by) for time of day.
-- Source: [DOCS]:1347-1350
---@param duration number
---@return nil
function tm.world.SetCycleDurationTimeOfDay(duration) end

---Set a global wind velocity. The wind velocity is a vector in world space,
---where the x, y and z components represent the wind direction and speed.
-- Source: [DOCS]:1318-1321
---@param windVelocity ModVector3
---@return nil
function tm.world.SetGlobalWind(windVelocity) end

---Returns the wind velocity at a position.
-- Source: [DOCS]:1324-1327
---@param position ModVector3
---@return ModVector3
function tm.world.GetWindVelocityAtPosition(position) end


--------------------------------------------------------------------------------
-- 9. tm.vector3
-- Source: [DOCS]:870-1035
--------------------------------------------------------------------------------

---A 3-axis vector (position, rotation, scale, etc.)
---@class ModVector3
---@field x number
---@field y number
---@field z number
---@operator add(ModVector3): ModVector3
---@operator sub(ModVector3): ModVector3
---@operator mul(number): ModVector3
---@operator div(number): ModVector3
---@operator unm: ModVector3

---@class ModVector3Constructor
tm.vector3 = {}

---Creates a vector3 from a string. String should be formatted as "(x, y, z)".
---Example input: "(4.5, 6, 10.8)"
-- Source: [DOCS]:877-880
---@param input string
---@return ModVector3
---@overload fun(x: number, y: number, z: number): ModVector3
---@overload fun(): ModVector3
function tm.vector3.Create(input) end

---Creates a vector3 pointing right: (1, 0, 0)
-- Source: [DOCS]:896-899
---@return ModVector3
function tm.vector3.Right() end

---Creates a vector3 pointing left: (-1, 0, 0)
-- Source: [DOCS]:901-903
---@return ModVector3
function tm.vector3.Left() end

---Creates a vector3 pointing up: (0, 1, 0)
-- Source: [DOCS]:905-907
---@return ModVector3
function tm.vector3.Up() end

---Creates a vector3 pointing down: (0, -1, 0)
-- Source: [DOCS]:909-911
---@return ModVector3
function tm.vector3.Down() end

---Creates a vector3 pointing forward: (0, 0, 1)
-- Source: [DOCS]:913-915
---@return ModVector3
function tm.vector3.Forward() end

---Creates a vector3 pointing back: (0, 0, -1)
-- Source: [DOCS]:917-919
---@return ModVector3
function tm.vector3.Back() end

-- -- Vector3 Operators --
-- These are exposed as named functions in the API but typically used via
-- operator overloads (+, -, *, /, ==, ~=, unary -)

---Negate a vector3.
-- Source: [DOCS]:927-929
---@param vector3 ModVector3
---@return ModVector3
function tm.vector3.op_UnaryNegation(vector3) end

---Add two vector3 values.
-- Source: [DOCS]:932-936
---@param first ModVector3
---@param second ModVector3
---@return ModVector3
function tm.vector3.op_Addition(first, second) end

---Subtract two vector3 values.
-- Source: [DOCS]:939-943
---@param first ModVector3
---@param second ModVector3
---@return ModVector3
function tm.vector3.op_Subtraction(first, second) end

---Multiply a vector3 by a scalar.
-- Source: [DOCS]:946-950
---@param vector3 ModVector3
---@param scaler number
---@return ModVector3
function tm.vector3.op_Multiply(vector3, scaler) end

---Divide a vector3 by a divisor.
-- Source: [DOCS]:953-957
---@param vector3 ModVector3
---@param divisor number
---@return ModVector3
function tm.vector3.op_Division(vector3, divisor) end

---Check equality of two vector3 values.
-- Source: [DOCS]:960-964
---@param first ModVector3
---@param second ModVector3
---@return boolean
function tm.vector3.op_Equality(first, second) end

---Check inequality of two vector3 values.
-- Source: [DOCS]:973-977
---@param first ModVector3
---@param second ModVector3
---@return boolean
function tm.vector3.op_Inequality(first, second) end

-- -- Vector3 Math --

---Returns the dot product of two vector3 values.
-- Source: [DOCS]:990-993
---@param otherVector ModVector3
---@return number
function tm.vector3.Dot(otherVector) end

---Returns the cross product of two vector3 values.
-- Source: [DOCS]:996-999
---@param otherVector ModVector3
---@return ModVector3
function tm.vector3.Cross(otherVector) end

---Returns the magnitude/length of the vector.
-- Source: [DOCS]:1002-1004
---@return number
function tm.vector3.Magnitude() end

---Returns the distance between two vectors.
-- Source: [DOCS]:1022-1026
---@param vector ModVector3
---@param otherVector ModVector3
---@return number
function tm.vector3.Distance(vector, otherVector) end

---Calculate a position between two points, moving no farther than maxDistanceDelta.
-- Source: [DOCS]:1007-1012
---@param vector ModVector3
---@param otherVector ModVector3
---@param maxDistanceDelta number
---@return ModVector3
function tm.vector3.MoveTowards(vector, otherVector, maxDistanceDelta) end

---Calculates the angle in degrees between two vectors.
-- Source: [DOCS]:1015-1019
---@param vector ModVector3
---@param otherVector ModVector3
---@return number
function tm.vector3.Angle(vector, otherVector) end

---Linearly interpolates between two vectors.
-- Source: [DOCS]:1029-1034
---@param vector ModVector3
---@param otherVector ModVector3
---@param t number
---@return ModVector3
function tm.vector3.Lerp(vector, otherVector, t) end

-- -- Vector3 Utility --

---Check equality with an object.
-- Source: [DOCS]:967-970
---@param obj any
---@return boolean
function tm.vector3.Equals(obj) end

---Get hash code.
-- Source: [DOCS]:980-982
---@return number
function tm.vector3.GetHashCode() end

---Get string representation.
-- Source: [DOCS]:985-987
---@return string
function tm.vector3.ToString() end


--------------------------------------------------------------------------------
-- 10. tm.quaternion
-- Source: [DOCS]:1037-1168
--------------------------------------------------------------------------------

---A quaternion rotation.
---@class ModQuaternion
---@field x number
---@field y number
---@field z number
---@field w number

---@class ModQuaternionConstructor
tm.quaternion = {}

---Creates a quaternion by manually defining its components.
-- Source: [DOCS]:1045-1051
---@param x number
---@param y number
---@param z number
---@param w number
---@return ModQuaternion
---@overload fun(x: number, y: number, z: number): ModQuaternion
---@overload fun(eulerAngle: ModVector3): ModQuaternion
---@overload fun(angle: number, axis: ModVector3): ModQuaternion
function tm.quaternion.Create(x, y, z, w) end

---Returns a vector3 representing the euler angles of the quaternion.
-- Source: [DOCS]:1075-1077
---@return ModVector3
function tm.quaternion.GetEuler() end

---Multiplies this quaternion with another quaternion and returns the resulting rotation.
-- Source: [DOCS]:1080-1083
---@param otherQuaternion ModQuaternion
---@return ModQuaternion
---@overload fun(scalar: number): ModQuaternion
function tm.quaternion.Multiply(otherQuaternion) end

---Returns the resulting quaternion from a lerp between two quaternions.
-- Source: [DOCS]:1086-1091
---@param firstQuaternion ModQuaternion
---@param secondQuaternion ModQuaternion
---@param t number
---@return ModQuaternion
function tm.quaternion.Lerp(firstQuaternion, secondQuaternion, t) end

---Returns the resulting quaternion from a slerp between two quaternions.
-- Source: [DOCS]:1094-1099
---@param firstQuaternion ModQuaternion
---@param secondQuaternion ModQuaternion
---@param t number
---@return ModQuaternion
function tm.quaternion.Slerp(firstQuaternion, secondQuaternion, t) end

---Returns a quaternion with all components negated.
-- Source: [DOCS]:1102-1104
---@return ModQuaternion
function tm.quaternion.Negate() end

---Adds together two quaternions component-wise.
-- Source: [DOCS]:1107-1110
---@param other ModQuaternion
---@return ModQuaternion
function tm.quaternion.Add(other) end

---Subtracts two quaternions from each other component-wise.
-- Source: [DOCS]:1113-1116
---@param other ModQuaternion
---@return ModQuaternion
function tm.quaternion.Subtract(other) end

---Divides all quaternion components by a scalar.
-- Source: [DOCS]:1125-1128
---@param scalar number
---@return ModQuaternion
function tm.quaternion.Divide(scalar) end

---Returns the inverse rotation of this quaternion.
-- Source: [DOCS]:1131-1133
---@return ModQuaternion
function tm.quaternion.Inverse() end

---Converts this quaternion to one with the same orientation but magnitude of 1.0.
-- Source: [DOCS]:1136-1138
---@return ModQuaternion
function tm.quaternion.Normalize() end

-- -- Quaternion Utility --

---Check equality with an object.
-- Source: [DOCS]:1155-1158
---@param obj any
---@return boolean
function tm.quaternion.Equals(obj) end

---Get hash code.
-- Source: [DOCS]:1161-1163
---@return number
function tm.quaternion.GetHashCode() end

---Get string representation.
-- Source: [DOCS]:1165-1168
---@return string
function tm.quaternion.ToString() end


--------------------------------------------------------------------------------
-- 11. tm.color
-- Source: [DOCS]:1171-1303
--------------------------------------------------------------------------------

---Represents a color.
---@class ModColor

---@class ModColorConstructor
tm.color = {}

---Creates a default ModColor.
-- Source: [DOCS]:1175-1177
---@return ModColor
---@overload fun(r: number, g: number, b: number, a: number): ModColor
function tm.color.Create() end

---Returns the red channel of the ModColor.
-- Source: [DOCS]:1194-1197
---@return number
function tm.color.R() end

---Returns the green channel of the ModColor.
-- Source: [DOCS]:1199-1201
---@return number
function tm.color.G() end

---Returns the blue channel of the ModColor.
-- Source: [DOCS]:1203-1205
---@return number
function tm.color.B() end

---Returns the alpha channel of the ModColor.
-- Source: [DOCS]:1208-1210
---@return number
function tm.color.A() end

-- -- Color Presets --

---Returns a ModColor set to white (1, 1, 1).
-- Source: [DOCS]:1213-1215
---@return ModColor
function tm.color.White() end

---Returns a ModColor set to black (0, 0, 0).
-- Source: [DOCS]:1218-1220
---@return ModColor
function tm.color.Black() end

---Returns a ModColor set to red (1, 0, 0).
-- Source: [DOCS]:1223-1225
---@return ModColor
function tm.color.Red() end

---Returns a ModColor set to green (0, 1, 0).
-- Source: [DOCS]:1228-1230
---@return ModColor
function tm.color.Green() end

---Returns a ModColor set to blue (0, 0, 1).
-- Source: [DOCS]:1233-1235
---@return ModColor
function tm.color.Blue() end

---Returns a ModColor set to yellow (1, 0.92, 0.016).
-- Source: [DOCS]:1238-1240
---@return ModColor
function tm.color.Yellow() end

---Returns a ModColor set to cyan (0, 1, 1).
-- Source: [DOCS]:1243-1245
---@return ModColor
function tm.color.Cyan() end

---Returns a ModColor set to magenta (1, 0, 1).
-- Source: [DOCS]:1248-1250
---@return ModColor
function tm.color.Magenta() end

---Returns a ModColor set to gray (0.5, 0.5, 0.5).
-- Source: [DOCS]:1253-1256
---@return ModColor
function tm.color.Gray() end

---Returns a ModColor set to clear (0, 0, 0, 0).
-- Source: [DOCS]:1259-1261
---@return ModColor
function tm.color.Clear() end

-- -- Color Math --

---Linear interpolation between two ModColors.
-- Source: [DOCS]:1264-1269
---@param a ModColor
---@param b ModColor
---@param t number
---@return ModColor
function tm.color.Lerp(a, b, t) end

---Convert HSV to RGB.
-- Source: [DOCS]:1272-1277
---@param hue number
---@param saturation number
---@param value number
---@return ModColor
function tm.color.HSVToRGB(hue, saturation, value) end

-- -- Color Utility --

---Get string representation.
-- Source: [DOCS]:1190-1192
---@return string
function tm.color.ToString() end

---Check equality with an object.
-- Source: [DOCS]:1287-1290
---@param obj any
---@return boolean
function tm.color.Equals(obj) end

---Get hash code.
-- Source: [DOCS]:1300-1302
---@return number
function tm.color.GetHashCode() end


--------------------------------------------------------------------------------
-- 12. OBJECT TYPES (Classes)
--------------------------------------------------------------------------------

-- -- ModPlayer --
-- Source: [DOCS]:1365-1372

---Class representing a player.
---@class ModPlayer
---@field connectionId string  @ Network connection identifier
---@field playerId number      @ Unique player ID for this session
---@field playerProfileId string @ Persistent Steam profile ID
---@field playerName string    @ Display name
---@field teamId number        @ Current team index
ModPlayer = {}


-- -- ModGameObject --
-- Source: [DOCS]:1374-1493

---GameObjects in the game environment.
---@class ModGameObject
ModGameObject = {}

---Despawns the object. This cannot be done on players.
-- Source: [DOCS]:1378-1380
---@return nil
function ModGameObject:Despawn() end

---Returns the gameObject's transform.
-- Source: [DOCS]:1383-1385
---@return ModTransform
function ModGameObject:GetTransform() end

---Sets visibility of the gameObject.
-- Source: [DOCS]:1388-1391
---@param isVisible boolean
---@return nil
function ModGameObject:SetIsVisible(isVisible) end

---Gets visibility of the gameObject.
-- Source: [DOCS]:1394-1396
---@return boolean
function ModGameObject:GetIsVisible() end

---Returns true if the gameObject or any of its children are rigidbodies.
-- Source: [DOCS]:1399-1401
---@return boolean
function ModGameObject:GetIsRigidbody() end

---Sets the gameObject's (and its children's) rigidbodies to be static or not.
-- Source: [DOCS]:1404-1407
---@param isStatic boolean
---@return nil
function ModGameObject:SetIsStatic(isStatic) end

---Returns true if the gameObject and all of its children are static.
-- Source: [DOCS]:1410-1412
---@return boolean
function ModGameObject:GetIsStatic() end

---Determines whether the gameObject lets other gameobjects pass through
---its colliders or not.
-- Source: [DOCS]:1415-1418
---@param isTrigger boolean
---@return nil
function ModGameObject:SetIsTrigger(isTrigger) end

---Returns true if the gameObject exists.
-- Source: [DOCS]:1421-1423
---@return boolean
function ModGameObject:Exists() end

---Sets the texture on the gameobject (Custom meshes only).
-- Source: [DOCS]:1426-1429
---@param textureName string
---@return nil
function ModGameObject:SetTexture(textureName) end

---Add a force to the game object as an impulse.
-- Source: [DOCS]:1432-1437
---@param x number
---@param y number
---@param z number
---@return nil
function ModGameObject:AddForceImpulse(x, y, z) end

---Add a force to the game object as a continuous force.
-- Source: [DOCS]:1440-1445
---@param x number
---@param y number
---@param z number
---@return nil
function ModGameObject:AddForce(x, y, z) end

---Add a force to the game object as an acceleration.
-- Source: [DOCS]:1448-1453
---@param x number
---@param y number
---@param z number
---@return nil
function ModGameObject:AddForceAcceleration(x, y, z) end

---Add a force to the game object as a velocity change.
-- Source: [DOCS]:1456-1461
---@param x number
---@param y number
---@param z number
---@return nil
function ModGameObject:AddForceVelocityChange(x, y, z) end

---Add a torque to the game object as an impulse.
-- Source: [DOCS]:1464-1469
---@param x number
---@param y number
---@param z number
---@return nil
function ModGameObject:AddTorqueImpulse(x, y, z) end

---Add a torque to the game object as a continuous force.
-- Source: [DOCS]:1472-1477
---@param x number
---@param y number
---@param z number
---@return nil
function ModGameObject:AddTorqueForce(x, y, z) end

---Add a torque to the game object as an acceleration.
-- Source: [DOCS]:1480-1485
---@param x number
---@param y number
---@param z number
---@return nil
function ModGameObject:AddTorqueAcceleration(x, y, z) end

---Add a torque to the game object as a velocity change.
-- Source: [DOCS]:1488-1493
---@param x number
---@param y number
---@param z number
---@return nil
function ModGameObject:AddTorqueVelocityChange(x, y, z) end


-- -- ModTransform --
-- Source: [DOCS]:1496-1748

---Represents a Transform (position, rotation, scale) of a GameObject.
---@class ModTransform
ModTransform = {}

-- World space position

---Sets the position of the transform (world space).
-- Source: [DOCS]:1500-1503
---@param position ModVector3
---@return nil
---@overload fun(self: ModTransform, x: number, y: number, z: number): nil
function ModTransform:SetPosition(position) end

---Gets the position of the transform (world space).
-- Source: [DOCS]:1514-1516
---@return ModVector3
function ModTransform:GetPosition() end

---Gets the position of the transform (world space). Alias.
-- Source: [DOCS]:1616-1618
---@return ModVector3
function ModTransform:GetPositionWorld() end

---Sets the position of the transform (world space). Alias.
-- Source: [DOCS]:1631-1634
---@param position ModVector3
---@return nil
---@overload fun(self: ModTransform, x: number, y: number, z: number): nil
function ModTransform:SetPositionWorld(position) end

-- World space rotation (euler)

---Sets the rotation of the transform (world space) using euler angles.
-- Source: [DOCS]:1519-1522
---@param rotation ModVector3
---@return nil
---@overload fun(self: ModTransform, x: number, y: number, z: number): nil
---@overload fun(self: ModTransform, rotation: ModQuaternion): nil
function ModTransform:SetRotation(rotation) end

---Gets the rotation of the transform (local space) as euler angles.
-- Source: [DOCS]:1533-1535
---@return ModVector3
function ModTransform:GetRotation() end

---Gets the euler angles rotation of the transform (world space).
-- Source: [DOCS]:1621-1623
---@return ModVector3
function ModTransform:GetEulerAnglesWorld() end

---Sets the euler angles rotation of the transform (world space).
-- Source: [DOCS]:1645-1648
---@param eulerAngles ModVector3
---@return nil
---@overload fun(self: ModTransform, x: number, y: number, z: number): nil
function ModTransform:SetEulerAnglesWorld(eulerAngles) end

-- World space rotation (quaternion)

---Gets the rotation quaternion of the transform (world space).
-- Source: [DOCS]:1544-1546
---@return ModQuaternion
function ModTransform:GetRotationQuaternion() end

---Gets the quaternion rotation of the transform (world space). Alias.
-- Source: [DOCS]:1626-1628
---@return ModQuaternion
function ModTransform:GetRotationWorld() end

---Sets the quaternion rotation of the transform (world space).
-- Source: [DOCS]:1659-1662
---@param rotation ModQuaternion
---@return nil
---@overload fun(self: ModTransform, x: number, y: number, z: number, w: number): nil
function ModTransform:SetRotationWorld(rotation) end

-- Scale

---Sets the scale of the transform (local space).
---Setting a non-uniform scale may break the object's physics.
-- Source: [DOCS]:1549-1552
---@param scale ModVector3
---@return nil
---@overload fun(self: ModTransform, x: number, y: number, z: number): nil
---@overload fun(self: ModTransform, scale: number): nil
function ModTransform:SetScale(scale) end

---Gets the scale of the transform (local space).
-- Source: [DOCS]:1568-1570
---@return ModVector3
function ModTransform:GetScale() end

-- Local space

---Gets the position of the transform (local space).
-- Source: [DOCS]:1674-1676
---@return ModVector3
function ModTransform:GetPositionLocal() end

---Sets the position of the transform (local space).
-- Source: [DOCS]:1694-1697
---@param position ModVector3
---@return nil
---@overload fun(self: ModTransform, x: number, y: number, z: number): nil
function ModTransform:SetPositionLocal(position) end

---Gets the euler angles rotation of the transform (local space).
-- Source: [DOCS]:1679-1681
---@return ModVector3
function ModTransform:GetEulerAnglesLocal() end

---Sets the euler angles rotation of the transform (local space).
-- Source: [DOCS]:1708-1711
---@param eulerAngles ModVector3
---@return nil
---@overload fun(self: ModTransform, x: number, y: number, z: number): nil
function ModTransform:SetEulerAnglesLocal(eulerAngles) end

---Gets the quaternion rotation of the transform (local space).
-- Source: [DOCS]:1684-1686
---@return ModQuaternion
function ModTransform:GetRotationLocal() end

---Sets the quaternion rotation of the transform (local space).
-- Source: [DOCS]:1722-1725
---@param rotation ModQuaternion
---@return nil
---@overload fun(self: ModTransform, x: number, y: number, z: number, w: number): nil
function ModTransform:SetRotationLocal(rotation) end

---Gets the scale of the transform (local space). Alias.
-- Source: [DOCS]:1689-1691
---@return ModVector3
function ModTransform:GetScaleLocal() end

---Sets the scale of the transform (local space). Alias.
-- Source: [DOCS]:1738-1741
---@param scale ModVector3
---@return nil
---@overload fun(self: ModTransform, x: number, y: number, z: number): nil
function ModTransform:SetScaleLocal(scale) end

-- Transform utilities

---Returns the point's position in world space.
-- Source: [DOCS]:1573-1577
---@param point ModVector3
---@return ModVector3
function ModTransform:TransformPoint(point) end

---Returns the direction's world space direction.
-- Source: [DOCS]:1580-1583
---@param direction ModVector3
---@return ModVector3
function ModTransform:TransformDirection(direction) end

-- Direction vectors (world space)

---Returns a normalized vector Forward (world space).
-- Source: [DOCS]:1586-1588
---@return ModVector3
function ModTransform:Forward() end

---Returns a normalized vector Back (world space).
-- Source: [DOCS]:1591-1593
---@return ModVector3
function ModTransform:Back() end

---Returns a normalized vector Left (world space).
-- Source: [DOCS]:1596-1598
---@return ModVector3
function ModTransform:Left() end

---Returns a normalized vector Right (world space).
-- Source: [DOCS]:1601-1603
---@return ModVector3
function ModTransform:Right() end

---Returns a normalized vector Up (world space).
-- Source: [DOCS]:1606-1608
---@return ModVector3
function ModTransform:Up() end

---Returns a normalized vector Down (world space).
-- Source: [DOCS]:1611-1613
---@return ModVector3
function ModTransform:Down() end


-- -- ModBlock --
-- Source: [DOCS]:1751-2131

---Represents a block in a structure.
---@class ModBlock
ModBlock = {}

-- Position/Rotation/Scale

---Gets the position of the block (world space).
-- Source: [DOCS]:1755-1757
---@return ModVector3
function ModBlock:GetPosition() end

---Gets the rotation of the block (local space).
-- Source: [DOCS]:1760-1762
---@return ModVector3
function ModBlock:GetRotation() end

---Gets the scale of the block (local space).
-- Source: [DOCS]:1765-1767
---@return ModVector3
function ModBlock:GetScale() end

-- Transform utilities

---Returns the point's position in world space.
-- Source: [DOCS]:1770-1773
---@param point ModVector3
---@return ModVector3
function ModBlock:TransformPoint(point) end

---Returns the direction's world space direction.
-- Source: [DOCS]:1776-1779
---@param direction ModVector3
---@return ModVector3
function ModBlock:TransformDirection(direction) end

-- Direction vectors (world space)

---Returns a normalized vector Forward in world space.
-- Source: [DOCS]:1782-1784
---@return ModVector3
function ModBlock:Forward() end

---Returns a normalized vector Back in world space.
-- Source: [DOCS]:1787-1789
---@return ModVector3
function ModBlock:Back() end

---Returns a normalized vector Left in world space.
-- Source: [DOCS]:1792-1794
---@return ModVector3
function ModBlock:Left() end

---Returns a normalized vector Right in world space.
-- Source: [DOCS]:1797-1799
---@return ModVector3
function ModBlock:Right() end

---Returns a normalized vector Up in world space.
-- Source: [DOCS]:1802-1805
---@return ModVector3
function ModBlock:Up() end

---Returns a normalized vector Down in world space.
-- Source: [DOCS]:1808-1810
---@return ModVector3
function ModBlock:Down() end

-- Identity

---Get the name of the block's type.
-- Source: [DOCS]:1813-1815
---@return string
function ModBlock:GetName() end

-- Color

---[DEPRECATED] Use SetPrimaryColor instead.
-- Source: [DOCS]:1818-1822
---@deprecated Use SetPrimaryColor instead
---@param r number
---@param g number
---@param b number
---@return nil
function ModBlock:SetColor(r, g, b) end

---Set the block's primary color.
-- Source: [DOCS]:1825-1830
---@param r number
---@param g number
---@param b number
---@return nil
---@overload fun(self: ModBlock, color: ModColor): nil
function ModBlock:SetPrimaryColor(r, g, b) end

---Set the block's secondary color.
-- Source: [DOCS]:1839-1844
---@param r number
---@param g number
---@param b number
---@return nil
---@overload fun(self: ModBlock, color: ModColor): nil
function ModBlock:SetSecondaryColor(r, g, b) end

---Get the block's primary color.
-- Source: [DOCS]:1864-1866
---@return ModColor
function ModBlock:GetPrimaryColor() end

---Get the block's secondary color.
-- Source: [DOCS]:1869-1871
---@return ModColor
function ModBlock:GetSecondaryColor() end

-- Mass & Buoyancy

---[In buildmode only] Set the block's mass.
-- Source: [DOCS]:1853-1856
---@param mass number
---@return nil
function ModBlock:SetMass(mass) end

---Get the block's mass.
-- Source: [DOCS]:1859-1861
---@return number
function ModBlock:GetMass() end

---[In buildmode only] Set the block's buoyancy.
-- Source: [DOCS]:1874-1877
---@param buoyancy number
---@return nil
function ModBlock:SetBuoyancy(buoyancy) end

---Get the block's buoyancy.
-- Source: [DOCS]:1880-1882
---@return number
function ModBlock:GetBuoyancy() end

-- Health

---[Deprecated] Use SetStartHealth instead.
-- Source: [DOCS]:1885-1888
---@deprecated Use SetStartHealth instead
---@param hp number
---@return nil
function ModBlock:SetHealth(hp) end

---Set the block's start health.
-- Source: [DOCS]:1891-1894
---@param hp number
---@return nil
function ModBlock:SetStartHealth(hp) end

---Reset the block's start health to its original value.
-- Source: [DOCS]:1897-1899
---@return nil
function ModBlock:ResetStartHealth() end

---Get the block's start health.
-- Source: [DOCS]:1902-1904
---@return number
function ModBlock:GetStartHealth() end

---Get the block's full health.
-- Source: [DOCS]:1907-1909
---@return number
function ModBlock:GetFullHealth() end

---Get the block's current health.
-- Source: [DOCS]:1944-1946
---@return number
function ModBlock:GetCurrentHealth() end

---Get the block health fraction normalised from 0 to its full health.
-- Source: [DOCS]:1949-1951
---@return number
function ModBlock:GetHealthFraction() end

---Returns true if the block has been damaged.
-- Source: [DOCS]:1935-1937
---@return boolean
function ModBlock:IsDamaged() end

---Returns true if the block is dead.
-- Source: [DOCS]:1939-1941
---@return boolean
function ModBlock:IsDead() end

---Give damage to a block.
-- Source: [DOCS]:1918-1926
---@param damageAmount number @ The amount of damage to deal
---@param damageDealerPlayerId number @ The player that dealt the damage, -1 for no player
---@param damageType string|ModDamageType @ The type of damage to deal, defaults to Generic
---@return nil
function ModBlock:DoDamageAmount(damageAmount, damageDealerPlayerId, damageType) end

---Instant kill the block.
-- Source: [DOCS]:1929-1931
---@return nil
function ModBlock:InstantKill() end

---Fully revives the block to its full health.
-- Source: [DOCS]:1912-1914
---@return nil
function ModBlock:Revive() end

-- Aerodynamics

---Manual AerodynamicBox definition.
-- Source: [DOCS]:1959-1966
---@class AerodynamicBox
---@field forward number
---@field back number
---@field up number
---@field down number
---@field left number
---@field right number

---Get the drag values of an aerodynamic box.
---WARNING: SetDrag/SetDragAll are expensive operations!
-- Source: [DOCS]:1968-1972
---@param aerodynamicBoxIndex number
---@return AerodynamicBox
function ModBlock:GetDrag(aerodynamicBoxIndex) end

---Get the drag values for all aerodynamic boxes.
-- Source: [DOCS]:1975-1978
---@return AerodynamicBox[]
function ModBlock:GetDragAll() end

---Expensive operation! Set the drag values of an aerodynamic box.
-- Source: [DOCS]:1981-1990
---@param aerodynamicBoxIndex number
---@param forward number
---@param back number
---@param up number
---@param down number
---@param left number
---@param right number
---@return nil
function ModBlock:SetDrag(aerodynamicBoxIndex, forward, back, up, down, left, right) end

---Expensive operation! Set all aerodynamic boxes to the defined drag values.
-- Source: [DOCS]:1993-2001
---@param forward number
---@param back number
---@param up number
---@param down number
---@param left number
---@param right number
---@return nil
function ModBlock:SetDragAll(forward, back, up, down, left, right) end

---Reset the drag of an aerodynamic box to default values.
-- Source: [DOCS]:2004-2007
---@param aerodynamicBoxIndex number
---@return nil
function ModBlock:ResetDrag(aerodynamicBoxIndex) end

---Reset the drag values of all aerodynamic boxes to default values.
-- Source: [DOCS]:2010-2012
---@return nil
function ModBlock:ResetDragAll() end

---Get the default drag values of an aerodynamic box.
-- Source: [DOCS]:2015-2019
---@param aerodynamicBoxIndex number
---@return AerodynamicBox
function ModBlock:GetDefaultDrag(aerodynamicBoxIndex) end

---Get the default drag values of all aerodynamic boxes.
-- Source: [DOCS]:2022-2025
---@return AerodynamicBox[]
function ModBlock:GetDefaultDragAll() end

---Get number of aerodynamic boxes.
-- Source: [DOCS]:2028-2030
---@return number
function ModBlock:GetNumberOfAerodynamicBoxes() end

-- Forces

---Add a force to the given block as an impulse.
-- Source: [DOCS]:2033-2038
---@param x number
---@param y number
---@param z number
---@return nil
function ModBlock:AddForce(x, y, z) end

---Add a torque to the given block as an impulse.
-- Source: [DOCS]:2041-2046
---@param x number
---@param y number
---@param z number
---@return nil
function ModBlock:AddTorque(x, y, z) end

-- Engine/Jet/Propeller/Gyro type detection and power

---Sets Engine power (only works on engine blocks).
-- Source: [DOCS]:2049-2052
---@param power number
---@return nil
function ModBlock:SetEnginePower(power) end

---Gets Engine power (only works on engine blocks).
-- Source: [DOCS]:2055-2057
---@return number
function ModBlock:GetEnginePower() end

---Sets Jet power (only works on jet blocks).
-- Source: [DOCS]:2060-2063
---@param power number
---@return nil
function ModBlock:SetJetPower(power) end

---Gets Jet power (only works on jet blocks).
-- Source: [DOCS]:2066-2068
---@return number
function ModBlock:GetJetPower() end

---Sets Propeller power (only works on propeller blocks).
-- Source: [DOCS]:2071-2074
---@param power number
---@return nil
function ModBlock:SetPropellerPower(power) end

---Gets Propeller power (only works on propeller blocks).
-- Source: [DOCS]:2077-2079
---@return number
function ModBlock:GetPropellerPower() end

---Sets Gyro power (only works on gyro blocks).
-- Source: [DOCS]:2082-2085
---@param power number
---@return nil
function ModBlock:SetGyroPower(power) end

---Gets Gyro power (only works on gyro blocks).
-- Source: [DOCS]:2088-2090
---@return number
function ModBlock:GetGyroPower() end

---Whether a block is an Engine block or not.
-- Source: [DOCS]:2093-2095
---@return boolean
function ModBlock:IsEngineBlock() end

---Whether a block is a Jet block or not.
-- Source: [DOCS]:2098-2100
---@return boolean
function ModBlock:IsJetBlock() end

---Whether a block is a Propeller block or not.
-- Source: [DOCS]:2103-2105
---@return boolean
function ModBlock:IsPropellerBlock() end

---Whether a block is a seat block or not.
-- Source: [DOCS]:2108-2110
---@return boolean
function ModBlock:IsPlayerSeatBlock() end

---Whether a block is a gyro block or not.
-- Source: [DOCS]:2113-2115
---@return boolean
function ModBlock:IsGyroBlock() end

-- Metadata & Structure

---Get the block's BlockMetaData.
-- Source: [DOCS]:1954-1956
---@return ModBlockMetaData
function ModBlock:GetBlockMetaData() end

---Returns structure a block belongs to.
-- Source: [DOCS]:2123-2125
---@return ModStructure
function ModBlock:GetStructure() end

---Returns true if the block exists.
---QUIRK: When you repair your structure, destroyed blocks are replaced with
---new ones, making old references invalid.
-- Source: [DOCS]:2118-2120
---@return boolean
function ModBlock:Exists() end

---Compare block equality.
-- Source: [DOCS]:2128-2131
---@param other ModBlock
---@return boolean
function ModBlock:Equals(other) end


-- -- ModBlockMetaData --
-- Source: [DOCS]:169-173

---Block metadata (name, GUID, description).
---@class ModBlockMetaData
ModBlockMetaData = {}

---Get the name of the block type.
---@return string
function ModBlockMetaData:GetName() end

---Get the GUID of the block type.
---@return string
function ModBlockMetaData:GetGuid() end

---Get the description of the block type.
---@return string
function ModBlockMetaData:GetDescription() end


-- -- ModStructure --
-- Source: [DOCS]:2134-2245

---Represents a Structure (a collection of blocks built by a player).
---@class ModStructure
ModStructure = {}

-- Position/Rotation/Scale

---Gets the position of the structure (world space).
-- Source: [DOCS]:2138-2140
---@return ModVector3
function ModStructure:GetPosition() end

---Gets the rotation of the structure (local space).
-- Source: [DOCS]:2143-2145
---@return ModVector3
function ModStructure:GetRotation() end

---Gets the scale of the structure (local space).
-- Source: [DOCS]:2148-2150
---@return ModVector3
function ModStructure:GetScale() end

-- Transform utilities

---Returns the point's position in world space.
-- Source: [DOCS]:2153-2156
---@param point ModVector3
---@return ModVector3
function ModStructure:TransformPoint(point) end

---Returns the direction's world space direction.
-- Source: [DOCS]:2159-2162
---@param direction ModVector3
---@return ModVector3
function ModStructure:TransformDirection(direction) end

-- Direction vectors (world space)

---Returns a normalized vector Forward in world space.
-- Source: [DOCS]:2165-2167
---@return ModVector3
function ModStructure:Forward() end

---Returns a normalized vector Back in world space.
-- Source: [DOCS]:2170-2172
---@return ModVector3
function ModStructure:Back() end

---Returns a normalized vector Left in world space.
-- Source: [DOCS]:2175-2177
---@return ModVector3
function ModStructure:Left() end

---Returns a normalized vector Right in world space.
-- Source: [DOCS]:2180-2182
---@return ModVector3
function ModStructure:Right() end

---Returns a normalized vector Up in world space.
-- Source: [DOCS]:2185-2187
---@return ModVector3
function ModStructure:Up() end

---Returns a normalized vector Down in world space.
-- Source: [DOCS]:2190-2192
---@return ModVector3
function ModStructure:Down() end

-- Structure operations

---Destroy the structure.
-- Source: [DOCS]:2195-2197
---@return nil
function ModStructure:Destroy() end

---Gets all blocks in the structure.
-- Source: [DOCS]:2200-2202
---@return ModBlock[]
function ModStructure:GetBlocks() end

---Add a force to the given structure as an impulse.
-- Source: [DOCS]:2205-2210
---@param x number
---@param y number
---@param z number
---@return nil
function ModStructure:AddForce(x, y, z) end

---Gets the velocity of the structure's center of mass in world space.
-- Source: [DOCS]:2218-2220
---@return ModVector3
function ModStructure:GetVelocity() end

---Gets the velocity of the player inside of the structure in world space.
-- Source: [DOCS]:2213-2215
---@return ModVector3
function ModStructure:GetSeatedPlayerVelocity() end

---Gets the speed of the player inside of the structure (m/s).
-- Source: [DOCS]:2223-2225
---@return number
function ModStructure:GetSpeed() end

---Get player index who owns this structure. Returns -1 if player is gone.
-- Source: [DOCS]:2228-2230
---@return number
function ModStructure:GetOwnedByPlayerId() end

---Returns the number of power cores of the structure.
-- Source: [DOCS]:2233-2235
---@return number
function ModStructure:GetPowerCores() end

---Returns the Center of Mass of the structure in world space.
-- Source: [DOCS]:2238-2240
---@return ModVector3
function ModStructure:GetWorldCenterOfMass() end

---Dispose the structure (cleanup).
-- Source: [DOCS]:2243-2245
---@return nil
function ModStructure:Dispose() end


-- -- ModRaycastHit --
-- Source: [DOCS]:2248-2269

---Represents a raycast hit result.
---@class ModRaycastHit
ModRaycastHit = {}

---Returns if the raycast hit something.
-- Source: [DOCS]:2252-2254
---@return boolean
function ModRaycastHit:DidHit() end

---Returns the hit position.
-- Source: [DOCS]:2262-2264
---@return ModVector3
function ModRaycastHit:GetHitPosition() end

---Returns the hit normal.
-- Source: [DOCS]:2257-2259
---@return ModVector3
function ModRaycastHit:GetHitNormal() end

---Returns the distance to the hit.
-- Source: [DOCS]:2267-2269
---@return number
function ModRaycastHit:GetHitDistance() end


-- -- ModDamage --
-- Source: [DOCS]:2406-2413

---Some type and amount of damage that has been dealt by a player at given
---position and direction.
---@class ModDamage
---@field damageType ModDamageType
---@field damageAmount number
---@field damagePosition ModVector3
---@field damageDirection ModVector3
---@field damageDealerPlayer ModPlayer
ModDamage = {}


-- -- UICallbackData --
-- Source: [DOCS]:1305-1312

---Callback data for when user is interacting with UI elements.
---@class UICallbackData
---@field playerId number
---@field id string
---@field type string
---@field value string
---@field data any
UICallbackData = {}


--------------------------------------------------------------------------------
-- tm.GetDocs()
-- Source: [DOCS]:1360-1362
--------------------------------------------------------------------------------

---Generates Trailmakers Mods API Lua Docs at runtime.
---@return string
function tm.GetDocs() end


--------------------------------------------------------------------------------
-- Global callback: update()
-- Called every tick by the mod runtime. Set tick rate with
-- tm.os.SetModTargetDeltaTime().
-- Source: [MOD], [WORKSHOP] universal pattern
--------------------------------------------------------------------------------

---Called every mod tick. Override this in your main.lua.
---@type fun()
function update() end


--------------------------------------------------------------------------------
-- 13. SPAWNABLE OBJECTS REFERENCE
-- Source: [SPAWN] trailmakers_spawnables.txt (578 entries)
--
-- All names are valid arguments to tm.physics.SpawnObject(position, name).
-- Organized by category below.
--
-- ---- TERRAIN / ROCKS ----
-- PFB_SpikyCanyon_1, PFB_PlateCanyon_01
-- PFB_Cliff_Bottom_Desert, PFB_Cliff_Bottom_Desert_Grass
-- PFB_Cliff_Bottom_Mud, PFB_Cliff_Bottom_Mud_Grass
-- PFB_Cliff_Med_Desert, PFB_Cliff_Med_Desert_Grass
-- PFB_Cliff_Med_Mud, PFB_Cliff_Med_Mud_Grass
-- PFB_Cliff_Top_Desert, PFB_Cliff_Top_Desert_Grass
-- PFB_Cliff_Top_Desert_Trees, PFB_Cliff_Top_Mud
-- PFB_Cliff_Top_Mud_Grass, PFB_Cliff_Top_Mud_Trees
-- PFB_Rock_Detail_Bush, PFB_Rock_Detail_Med_Desert_00
-- PFB_Rock_Detail_Med_Desert_00_Grass, PFB_Rock_Detail_Med_Desert_01
-- PFB_Rock_Detail_Med_Desert_01_Grass, PFB_Rock_Detail_Med_Mud_00
-- PFB_Rock_Detail_Med_Mud_00_Grass, PFB_Rock_Detail_Med_Mud_01
-- PFB_Rock_Detail_Med_Mud_01_Grass, PFB_Rock_Detail_Med_Mud_01Test
-- PFB_Rock_Detail_Top_Desert, PFB_Rock_Detail_Top_Mud
-- PFB_Rock_Detail_Top_Mud1, PFB_Rock_Desert_Arc
-- PFB_Rock_Desert_Med, PFB_Rock_Desert_VerySmall
-- PFB_Rock_Mud_Large, PFB_SmallRock_Spawner_01
-- PFB_StoneCliff_01, PFB_StoneCliff_04
-- PFB_StoneCliff_FlatTopAngle, PFB_StoneCliffFlat_01
-- PFB_StoneCliffFlat_02, PFB_StoneCliffFlat_03
-- PFB_SimpleStoneHighSeas, PFB_StoneWall_Large
-- PFB_AlgarveCliff_Tiki, PFB_AlgarveCliff_Tiki_2
-- PFB_AlgarveCliff_Tiki_3, PFB_Cliff_Bottom_Tiki
-- PFB_Rock_Med_Tiki, PFB_Rock_VerySmall_Tiki
-- PFB_SkullCliff, PFB_Cliff_Top_fungus
-- PFB_FloatingIsland_02_fungus, PFB_FloatingIsland_03_fungus
-- PFB_FloatingIsland_05_fungus, PFB_Rock_Detail_Med_fungus_02
-- PFB_Rock_Detail_Top_fungus, PFB_RockArch_01_fungus
-- PFB_RockPillar_fungus, PFB_StoneCliff_fungus
-- PFB_cliffs01_volcano, PFB_cliffs02_volcano
-- PFB_cliffs03_volcano, PFB_spikes01_volcano
-- PFB_Iceberg_01, PFB_IceCaveLidLong, PFB_IceCaveLidRound
-- PFB_IceCliffFlat_02, PFB_IceCliffFlat_03, PFB_LongCaveICE
-- PFB_DesertRock_01..05
-- PFB_CrystalRock_8, PFB_CrystalRock_9
-- PFB_CrystalClusterBlue, PFB_CrystalClusterPink
-- PFB_CrystalSmall_blue, PFB_CrystalSmall_pink
-- PFB_CrystalPlanet_Rock_01..04
-- PFB_MoonCliff_01..06
-- PFB_Pike_Cliff_Med, PFB_Pike_Cliff_1..5
-- PFB_Pike_Floating, PFB_Pike_Rock_1..2, PFB_Pike_Donut
-- PFB_Sky_Cliff_1..5, PFB_Sky_Float_1..5, PFB_Sky_Arc
-- PFB_Tooth_Big_01..03, PFB_Tooth_Small_01..03
--
-- ---- TREES / VEGETATION ----
-- PFB_CharredBush, PFB_CharredStump, PFB_CharredTree, PFB_CharredTree2
-- PFB_Palm1, PFB_Palm2, PFB_PalmFern_Big, PFB_PalmFern_Medium
-- PFB_BulkyPineTree_FBX, PFB_SlenderPineTree-Final_FBX
-- PFB_Tall__Lush_FatPine_1, PFB_Tall__Pruny_SlenderPine_2
-- PFB_Tall__Pruny_SlenderPine_Impostor, PFB_Tall_SlenderPine_1
-- PFB_BlueBerryShrub_01, PFB_BlueBerryShrub_02_Noco
-- PFB_Cactus_Ball, PFB_Cactus_Bush, PFB_Cactus_Bush_Populate
-- PFB_Cactus_Mini, PFB_Cactus_Mushroom_Tree, PFB_Cactus_Small
-- PFB_Cactus_Star_Plant, PFB_Cactus_Tree
-- PFB_Desert_Bush_Fir, PFB_Bushy
-- PFB_INS_Savannah_Bush_Small
-- PFB_INS_Savannah_Tree_Short, PFB_INS_Savannah_Tree_Short_brown
-- PFB_INS_Savannah_Tree_Short_Purple, PFB_INS_Savannah_Tree_Short_Yellow
-- PFB_INS_Savannah_Tree_Tall, PFB_INS_Savannah_Tree_Tall_Brown
-- PFB_INS_Savannah_Tree_Tall_Purple, PFB_INS_Savannah_Tree_Tall_Yellow
-- PFB_Pine_Bush, PFB_Pine_Bush_TEST, PFB_Savannah_Tree
-- PFB_Mushroom_5m_01..03, PFB_Mushroom_30m_01..03
-- PFB_Mushroom_60m_01..03
-- PFB_Mushroom_Big_A..C, PFB_Mushroom_Small_A..C
-- PFB_TropicalFlower_1..4, PFB_HangingGreenery, PFB_Roots
-- PFB_INS_Savannah_Fern, PFB_Cactus_Mushroom_Aviation
-- PFB_Cactus_Bush_Aviation, PFB_Short_Slender_Pine_1
-- PFB_Tall__Pruny_SlenderPine_Snow
-- PFB_Christmas_Short_Lush_Pine, PFB_Christmas_Short_Slender_Pine
-- PFB_Christmas_Tall_SlenderPine
-- PFB_Trees_Oak_01, PFB_Trees_Oak_02, PFB_Trees_Pine_01
-- PFB_Trees_HeroOak_01
-- PFB_Vegetation_Bush_01, PFB_Vegetation_Bush_02
-- PFB_Desert_Coral_Large_01..07
-- PFB_Desert_Coral_Small_A_01..03, PFB_Desert_Coral_Small_B_01..03
-- PFB_Desert_Coral_Small_C_01..02
--
-- ---- CORAL / UNDERWATER ----
-- PFB_CoralReef1..3
-- PFB_coralAnemoneA01..02, PFB_coralAnemoneB01..02
-- PFB_coralEggA01..02, PFB_coralEggB01..02
-- PFB_coralFormation01..02
-- PFB_coralRockA01..02, PFB_coralRockB01..02
-- PFB_coralRockC01..02, PFB_coralRockD01..02, PFB_coralRockE01..02
-- PFB_coralRockPlatform01..06
-- PFB_coralTuberA01..02
-- PFB_WavyBottomPlantGreenBubbleWeed, PFB_WavyBottomPlantGreenCactus
-- PFB_WavyBottomPlantGreenLadder, PFB_WavyBottomPlantGreenLeafy
-- PFB_WavyBottomPlantGreenRedGrass
-- PFB_WavyBottomPlantPurpleSquareEnd
-- PFB_WavyBottomPlantRedBubbleEnds, PFB_WavyBottomPlantRedShredded
-- PFB_GiantPearl
--
-- ---- EXPLOSIONS (6) ----
-- PFB_Explosion_Large, PFB_Explosion_Medium, PFB_Explosion_Micro
-- PFB_Explosion_SeatDeath, PFB_Explosion_Small, PFB_Explosion_XL
-- PFB_PoisonCloud_Explosion
--
-- ---- DISPENSABLES ----
-- PFB_Dispensable-BeachBall, PFB_Dispensable-ConcreteWall
-- PFB_Dispensable-Cone, PFB_Dispensable-MetalCrate
-- PFB_Dispensable-Mine, PFB_Dispensable-Present
-- PFB_Dispensable-Torpedo
-- PFB_DispensableBall, PFB_DispensableBoulder
-- PFB_DispensableCube, PFB_DispensableSnowball, PFB_DispensableSphere
--
-- ---- PHYSICS OBJECTS ----
-- PFB_Barrel, PFB_ExplosiveBarrel, PFB_MagneticCube
-- PFB_Mine, PFB_GoldNugget_Small, PFB_GoldChest
-- PFB_MovePuzzleBall, PFB_MovePuzzleBounds
-- PFB_MovePuzzleStart, PFB_MovePuzzleTarget
-- PFB_PropWheelStack, PFB_Rubble
--
-- ---- CRATES ----
-- PFB_ExplosiveCrate, PFB_IronCrate, PFB_PowerCoreCrate
-- PFB_WoodCrate, PFB_WoodCrate_Not_Empty
-- PFB_Container_Blue, PFB_Container_Blue_Dynamic
-- PFB_Container_Orange, PFB_Container_Orange_Dynamic
-- PFB_Container_Red, PFB_Container_Red_Dynamic
-- PFB_Crate_01_Merchant, PFB_Crate_02_Merchant
--
-- ---- RACE / CHALLENGE ----
-- PFB_RacingCheckPoint, PFB_RacingCheckPoint_Halfcircle
-- PFB_ChallengeCheckpoint, PFB_ChallengeCheckpoint_HalfCircle
-- PFB_ChallengeCheckpoint_Round
-- PFB_ChallengeCheckPointEnd_Flat, PFB_ChallengeCheckpointEnd_Round
-- PFB_ChallengeCheckPointStart
-- PFB_ChallengeCheckpoint_Expedition2
-- PFB_ChallengeCheckpoint_Floating_Expedition2
-- PFB_ChallengeCheckpoint_Flying_Expedition2
-- PFB_ChallengeCheckPointEnd_Floating_Expedition2
-- PFB_ChallengeSignUpExpedition
-- PFB_ChallengeSignUpExpedition_Floating_Expedition2
-- PFB_ChallengeLimitedBlockTag
-- PFB_KingOfTheHill_CrownPickup
-- PFB_Beacon, PFB_TreasureBeacon, PFB_Waypoint
-- PFB_GoldPickup, PFB_EpicJumpSequence
-- PFB_RaceTrackStartline, PFB_Race_TurnSign
-- PFB_RingofFire, PFB_BlockHunt
-- PFB_BasketBallHoop, PFB_Rallyramp
-- PFB_F1_BumpyFence
-- PFB_RacePropTyre-Blue, PFB_RacePropTyre-Blue_LOWRES
-- PFB_RacePropTyre-Yellow
--
-- ---- NPCs / ANIMALS ----
-- PFB_NuggetThief, PFB_Runner, PFB_Runner-Monkey
-- PFB_Whale, PFB_Sheep, PFB_Birdo_Medium
-- PFB_ChaserAI, PFB_ChaserAIBall, PFB_ChaserAIDead
-- PFB_Chirpo_Blue, PFB_Chirpo_Dark, PFB_Chirpo_LightGreen
-- PFB_Chirpo_Orange, PFB_Chirpo_Purple, PFB_Chirpo_White
-- PFB_Chirpo_Spacer_Blue, PFB_Chirpo_Spacer_Dark
-- PFB_Chirpo_Spacer_LightGreen, PFB_Chirpo_Spacer_Orange
-- PFB_Chirpo_Spacer Purple, PFB_Chirpo_Spacer_White
-- PFB_Chirpo_CaptainSpeck, PFB_Chirpo_Stationary
--
-- ---- STRUCTURES / BUILDINGS ----
-- PFB_BigWindMill, PFB_Windmill3, PFB_LightHouse
-- PFB_ShipWreck, PFB_Carrier, PFB_Blimp
-- CliffColoniesHouse_Large_01..02, CliffColoniesHouse_MayorHouse
-- CliffColoniesHouse_Small_01..03
-- PFB_ExplorationBase
-- PFB_DeliveryStationGREEN, PFB_DeliveryStationBLUE
-- PFB_DeliveryStationYELLOW, PFB_DeliveryStationRED
-- PFB_IceHarbour_Base, PFB_IceHarbour_Platform
-- PFB_IceHarbour_Platform_End_01..04
-- PFB_IceHarbour_Platform_Pole
-- PFB_IceHarbour_Platform_Stairs_01..02
-- PFB_IceHarbour_Ramp_01..02
-- PFB_IceHarbour_Antenna_01..03
-- PFB_IceHarbour_Pipe, PFB_IceHarbour_Pipe_and_BlueLights
-- PFB_IceHarbour_Pipe_and_YellowLights
-- PFB_IceHarbour_Pipe_Corner
-- PFB_IceHarbour_Pipe_Corner_and_BlueLights
-- PFB_IceHarbour_Pipe_Corner_and_YellowLights
-- PFB_IceHarbour_Pipe_GroundPiece
-- PFB_IceHarbour_Pipe_GroundPiece_and_BlueLights
-- PFB_IceHarbour_Pipe_GroundPiece_and_YellowLights
-- PFB_VolcanoHarbour_Base, PFB_VolcanoHarbour_Chain_01..02
-- PFB_VolcanoHarbour_Mooring_01..02, PFB_VolcanoHarbour_Rope
-- PFB_VolcanoHarbour_Tire, PFB_VolcanoHarbour_Tire_Dynamic
-- PFB_VolcanoHarbour_WoodPlank_01..02
-- PFB_VolcanoHarbour_Silo_01_Blue..Red
-- PFB_VolcanoHarbour_Silo_02_Blue..Red
-- PFB_VikingHarbour, PFB_VikingHarbour_Gate
-- PFB_VikingHarbour_HelmetSkull
-- PFB_VikingHarbour_Shield_01..04
-- PFB_vikingStatue_01
-- HeroTower_Skyland
-- PFB_Helipad, PFB_SatelliteDish
-- PFB_Scaffolding_Section
--
-- ---- MODULAR ROAD / TRACK ----
-- PFB_Modular90DegreeTurn, PFB_ModularBigSlope
-- PFB_ModularPillar, PFB_ModularSlopeUp-Angled
-- PFB_ModularSlopeUp, PFB_ModularSlopeUpEnd
-- PFB_ModularSmallSlope
-- PFB_ModularStraightRoad_Guards-2x, PFB_ModularStraightRoad_Guards
-- PFB_ModularStraightRoad_NoGuards-2x, PFB_ModularStraightRoad_NoGuards
-- PFB_ModularT-Cross
-- PFB_Modular_90DegreeWall, PFB_Modular_90DegreeWallMIRROR
-- PFB_Modular_BigWall, PFB_Modular_Entrance
-- PFB_Modular_PillarLight, PFB_Modular_Ramp, PFB_Modular_SmallWall
-- PFB_ModularSlopeUp_Highseas, PFB_ModularSmallSlope_Highseas
-- PFB_SmallSinglebeam_Highseas
-- PFB_BearingBeams, PFB_BearingBeamSingle, PFB_SmallBeamSingle
-- PFB_SpinnerArena
--
-- ---- WOODEN / BRIDGE ----
-- PFB_WoodPlank_01, PFB_WoodPlank_04
-- PFB_WoodPlank_Dark_01, PFB_WoodPlank_Dark_04
-- PFB_WoodPole_01, PFB_WoodPole_Dark_01
-- PFB_WoodPole, PFB_WoodPole_Dark
-- PFB_WoodenBoard, PFB_WoodenFence
-- WoodenBridge_Large, WoodenBridge_Pole
-- PFB_CurvedBridge, PFB_BridgePillar
--
-- ---- LED SIGNS ----
-- PFB_LED_PIXEL_ARROW_X5_Yellow, PFB_LED_PIXEL_ARROW_X5
-- PFB_LED_Sign_ARROW_LED
-- PFB_LED_Sign_3Bridges, PFB_LED_Sign_Air, PFB_LED_Sign_Beach
-- PFB_LED_Sign_Boat, PFB_LED_Sign_Canal, PFB_LED_Sign_Drag
-- PFB_LED_Sign_Track, PFB_LED_Sign_Valley
-- LED_Sign_Bulldawg, LED_Sign_Butterfly, LED_Sign_Doge
-- LED_Sign_Dragon, LED_Sign_Hygge, LED_Sign_KeepGoingAB
-- LED_Sign_LiveYoung, LED_Sign_LookStupid, LED_Sign_MyDust
-- LED_Sign_NoPeril, LED_Sign_Rolling_Motar, LED_Sign_TheresAWay
-- LED_Sign_Towel, LED_Sign_Unicorn, LED_Sign_WatchForSigns
-- LED_Sign_DitchVibe
-- PFB_DetourSign, PFB_RoadClosedSign
--
-- ---- SPACE ----
-- PFB_SpaceShipHighseas, PFB_GiantSpaceCraftRuin, PFB_SpaceWreckage2
-- PFB_Spherecraft
-- PFB_SpaceRing_01..03
-- PFB_MoonBase_Plank_01..08
-- PFB_SpacePipe_Cornor1..3, PFB_SpacePipe_Long, PFB_SpacePipe_Short
--
-- ---- BONES / SKELETAL ----
-- PFB_Bones_Flipper, PFB_Bones_GiantRibcage, PFB_Bones_Rib
-- PFB_Bones_Skeleton_01..02, PFB_Bones_Spine_01..02
-- PFB_BoneRing, PFB_GiantBone_1..3
--
-- ---- LEVEL OBJECTS / MISC ----
-- PFB_SquareCannon, PFB_Catapult, PFB_CatapultStraight
-- PFB_Grinderv2, PFB_Hammer, PFB_Heightjump
-- PFB_Pusher, PFB_Pushersx5, PFB_Pushersx5_Below
-- PFB_Spinner, PFB_Tube3-NoHoles2
-- PFB_ArkCollected, PFB_KungfuFlaglol, PFB_FlagTwin
-- PFB_ChillbitchRoad
-- PFB_WindBoxTrigger
-- PFB_ConstructionRoadClosedFenceDestructable
-- PFB_Loop_Dangerzone, PFB_ConstructionCylinderCone
-- PFB_ConsoleCorner, PFB_ConsoleModular
-- PFB_AirventDouble, PFB_AirventSingle, PFB_PipeThruHill
-- PFB_Pipe_Corner_1..3, PFB_Pipe_Long, PFB_Pipe_Short, PFB_Pipe_Valve
-- PFB_PipeHollowBended
-- PFB_Red_EnergyShield, PFB_FlameThrowerEffect
-- PFB_TimelinePodLandingClimbIsland
-- PFB_Lava, PFB_Lava_Underwater
-- PFB_CrashedMayorPlane, PFB_CrashedPlaneWing
-- PFB_HS_Clam, PFB_HS_ClamClosed
-- PFB_Round2Tower, PFB_RaceTrack-Speaker
-- PFB_TestCollisionTimeline
-- DesertHouse_SolarPanel_02, DesertHouse_Antenna_02, DesertHouse_PipeSquare
-- DesertHouse_WallAsset_01
-- PFB_Fence_Part_Meadowse_01
-- Waterfall_Ruins
-- Skyland_ClothsLine_01
-- GFX_Dynamic_Water_Buoy
--
-- ---- SALVAGE ITEMS ----
-- PFB_SalvageItem_Ball, PFB_SalvageItem_Ball_L, PFB_SalvageItem_Ball_M
-- PFB_SalvageItem_Compound_3
-- PFB_SalvageItem_Compound_Variant_1..2
-- PFB_SalvageItem_Explosive, PFB_SalvageItem_Explosive_M
-- PFB_SalvageItem_L Variant, PFB_SalvageItem_M Variant
-- PFB_SalvageItem_Small, PFB_SalvageItem_Timed
-- PFB_SalvageItem_XL Variant
-- PFB_HS_Salvage_Root_Wood_LogMedium
-- PFB_HS_Salvage_Root_Wood_LogSmall
-- PFB_HS_Salvage_Root_Wood_LogLarge
--
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- 14. AUDIO EVENTS REFERENCE
-- Source: [AUDIO] trailmakers_audio.txt (1,706 entries)
--
-- All names are valid arguments to tm.audio.PlayAudioAtPosition() and
-- tm.audio.PlayAudioAtGameobject().
-- For the complete list, see trailmakers_audio.txt in the mods directory.
--
-- ---- EXPLOSIONS ----
-- Explosion_small, Explosion_Flak, Explosion_Underwater, Explosion_EMP
-- Explosion_poisonCloud
--
-- ---- WEAPONS / COMBAT ----
-- WPN_Minigun_WW2_Start/Stop, WPN_SmallCannon_WW2_Loop_Start/Stop
-- WPN_GrenadeLauncher_Shoot, WPN_EnergyBlade_* (multiple variants)
-- WPN_SeaMine_*, WPN_Landmine_*, WPN_DepthCharge_*
-- WPN_Seamine_Dispensable_Triggered
-- BLCK_WPN_ShieldBattery_*, BLCK_WPN_LaserBlaster_Shoot
-- BLCK_WPN_Shotgun_OutOfAmmo, BLCK_WPN_EMPCannon_Fire
-- BLCK_WPN_Small_EMPCannon_Fire
-- Block_Cannon_bullet_destroy, Block_Tank_Cannon_Fire_Multi
-- Block_BombRack_Fire, Block_RocketLauncher_Shoot
-- TankCannonSmall_Shoot
-- Block_Flamethrower_Stop, Block_Flamethrower_OutOfAmmo_Oneshot
-- Block_SprayNPray_Start/Stop
-- STRC_Bullet_Wizzby_Generic/Underwater/RocketLauncher
-- STRC_Bullet_Impact_Stone/Wood/Mud/Ice
-- Structure_Damage_Hitmarker_PlayerHit_BlockDamaged/BlockKilled
--
-- ---- ENGINES / PROPULSION ----
-- PRP_Engine_Raw_*, PRP_Engine_BullDawg_*, PRP_Engine_Dragon_*
-- PRP_Jet_Raw_*, PRP_Jet_Mini_*, PRP_Jet_Gimbal_*, PRP_Jet_Large_*
-- PRP_Jet_Dragon_*, PRP_Jet_Rocket_*
-- PRP_Gyro_Stabilizer_Start
-- PRP_HugePropellerEngine_Start
-- PRP_Misc_Balloon_Stop, PRP_Wormhole_*
-- BLCK_PRP_Propeller_*, BLCK_PRP_BigPropeller_*
-- BLCK_PRP_TailPropeller_*
-- Engine_UnderWater_*, Engine_Screw_UnderWater_*
-- Engine_JetTiny_Activate
-- Hoverblock_Start/Stop/StructureStart
-- Block_HeliRotator_start
-- Block_Sail_Start
--
-- ---- LEVEL OBJECTS ----
-- LvlObj_Fireplace, LvlObj_Pusher_*, LvlObj_Rotator_*
-- LvlObj_Spinner_*, LvlObj_Grinder_*, LvlObj_Hammer
-- LvlObj_Catapult, LvlObj_Heightometer_trigger_01..10
-- LvlObj_Basketball_trigger_A..F
-- LvlObj_RingOfFire_*, LvlObj_WindZone_*
-- LvlObj_TeleportStation_*, LvlObj_Landmine_*
-- LvlObj_WoodCrate_explode, LvlObj_PowerCoreCrate_onPickup
-- LvlObj_Flag_*, LvlObj_Spacepod
-- LvlObj_WaterSplash_Small, LvlObj_ConfettiCelebration
-- LvlObj_SmokeFire
-- LvlObj_SoftPenalty_Cactus_collision
-- LvlObj_SoftPenalty_smalltree_collision
-- LvlObj_SoftPenalty_Cactus_ball_collision
-- LvlObj_LandmineExplosion_explosion
-- LvlObj_Geyser_*, LvlObj_Whirlpool
-- LvlObj_City_Enter/Exit, LvlObj_HVAC_Start
-- ModdingWind_Start, GuidingWind_Stop
--
-- ---- AMBIENT / ENVIRONMENT ----
-- Amb_Grass_Basic_Start/Stop, Amb_Field_Grass
-- Amb_DangerZone_start/stop, Amb_Rally_start/stop
-- Amb_Basicwind_start, Amb_BasicWind_Exploration_start
-- Amb_HeavyWinds_Start/Stop, Amb_HowlingPeaks_Start/Stop
-- Amb_Rain_Start, Amb_River_Start/Stop
-- Amb_Lake_Start, Amb_LakeSide*, Amb_CavePond_*
-- Amb_Cave_Stop, Amb_Beach_Indoor_*
-- Amb_Lava_start/stop, Amb_LavaInside_stop
-- Amb_Volcano_Base_Stop
-- Amb_Desert_Basic_*, Amb_Desert_Drone1..2_*
-- Amb_Desert_Forrest_Basic_Ambience_Play
-- Amb_Forrest_*, Amb_PineForest_*, Amb_SkylandsForest_*
-- Amb_Marsh_*, Amb_Animals_*
-- Amb_BattleIsland_Start/Stop
-- Amb_ChristmasSong_start
-- HighSeas_Wind_Start/Stop, Whirlpool_Start/Stop
-- Waves_Ocean_Start
-- AI_Env_PalmTree_WindLoop, AI_Env_SavannahTree_WindLoop
-- AI_Env_SateliteDish_Start/Stop
-- AI_Amb_* (various ambient zones)
-- Amb_PIO_* (Pioneers DLC ambient sounds, 100+ entries)
-- Amb_Wind_Shared_Tree_*
--
-- ---- UI ----
-- UI_Rally_*, UI_Race_*, UI_FinalLap, UI_LapCounter
-- UI_MultiPl_*, UI_Deathmatch_*
-- UI_SpaceShip_Unlock_Start/Stop
-- UI_BLDR_Config_*, UI_Aviation_*
--
-- ---- NPC / ANIMALS ----
-- NPC_Animal_Chaser_*, NPC_Animal_Whale_*
-- NPC_Animal_Sheep_*, NPC_Animal_Seagull_*
-- NPC_Animal_Runner_*, NPC_Animal_Monkey_*
-- NPC_Animal_Vulture_*, NPC_Animal_NuggetTheif_*
-- NPC_Animal_SandScraper_*, NPC_Animal_HighSeas_Whale_Start
-- NPC_Enemy_* (enemy AI sounds: Speeder, Blimp, FlakCannon, etc.)
-- NPC_InGame_* (civilian and Terry NPC sounds)
-- NPC_Intercom_*, NPC_Overlord_*, NPC_Miniboss_*
-- NPC_Waddle_*, NPC_Froggit_*
-- Birds_Coockoo3D_*, Birds_NorthernHawk_3D_*
--
-- ---- BUILD MODE ----
-- Build_attach_generic, Build_rotate_generic, Build_Move_generic
-- Build_duplicate_generic, Build_Lift_generic
-- Build_block_dissolve_start/stop
-- Build_BasicBlock1x2_*, Build_BasicBlock2x4_*
-- Build_Wheel_*, Build_HeliBlade_*, Build_ModularWing_*
-- Build_JetEngine_*, Build_JetEngineMini_*, Build_V8Engine_*
-- Build_MiniEngine_*, Build_EngineNinja_*, Build_EngineGeneric_*
-- Build_Cannon_*, Build_Light_*, Build_DriverSeat_*
-- Build_FuelContainer_*, Build_ShieldPlate1x2_*
-- Build_Suspension_*, Build_PistonBlock_*
-- Build_smallHinge_*, Build_LargeHinge_*
-- Build_StraightPole_*, Build_ActiveBlockButton_*
-- Build_SpawnBlock_generic, Build_ButtonDuplicate_generic
-- Build_ButtonCenter, Build_ButtonErase
-- Build_Welding_Start, Bulild_Welding_Stop
-- Build_CookBook_AutomaticStep, Build_CookBookr_StepCorrect
-- Build_ToneGenerator_Select, Build_ChangeConfig_ToneGenerator
-- Build_Parrot_Select, Build_ChangeConfig_Parrot
-- Build_rotate_Logic, Build_rotate_weapon, Build_rotate_fire
-- Build_rotate_flag, Build_attach_Weapon, Build_attach_Fire
-- Build_attach_Flag, Build_attach_Logic
-- BLDR_Action_BlockSelect
--
-- ---- STRUCTURE ----
-- OnStructureSpawn, OnStructureEnterPlay, OnStructureEnterBuild
-- Structure_UnOccupied, STRUC_Flip_Start/Stop
-- STRUC_Repair, STRUC_TransformRepair_Ready/Activate
-- StructureDamage_one/few/many, StructureEdgeDie_one/few/many
-- STRC_Emp_Start/End, Block_Magnet_Start/Hit
--
-- ---- WHEELS / TRACKS ----
-- Wheel_Basic_Start/Stop, Wheel_Basic_brakeStop
-- Wheel_Basic_puncture, Wheel_Basic_surfaceChange
-- Wheel_Basic_LeaveGround, Wheel_Basic_OnGroundPressureChanged
-- BLCK_TankThread_Start/Stop, BLCK_Ski_Stop
--
-- ---- BLOCK MECHANICS ----
-- Block_PistonBlock_start/stop, Block_SmallHinge_stop
-- Block_LargeHinge_steer
-- Block_SpinningBlock_destroy, Block_RotatingHingeJoint_Servo_destroy
-- Block_PoweredModularWing_activeStart
-- Block_ModularWing_activeStart/destroy
-- Block_WingFin_activeStart/Stop/destroy
-- BLCK_Mech_Servo_*, BLCK_MECH_PowerConduit_*
-- BLCK_Dispenser_Default, BLCK_DEV_RemoteCameraBlock_Activate
-- InputSeat_SonicBoom_Client/Server
--
-- ---- VANITY / MUSIC ----
-- Vanity_Horn1_*, Vanity_Horn_Yelper_Start
-- Vanity_FiretruckSiren_Start
-- Vanity_GhettoBlaster1..11_* (Start/Stop/pause/unPause)
-- Vanity_FroggitBlaster_Unpause
-- Vanity_SeaShantyGramophone_Unpause/pause
-- Vanity_Shipbell_Play
-- Vanity_FireBlock_Play/Stop, Vanity_BubbleMachine_Play
-- Vanity_MadScientist_Play
-- Vanity_ToneBlock_Synth_Stop
-- BLCK_Vanity_Flare_Shot, BLCK_Vanity_Firework_Shoot/Explode
-- MUSIC_testevent, Test_Music_BoomBox
-- Test_PlayBeep, Test_3DBeep
--
-- ---- CUTSCENE / CINEMATIC ----
-- AVI_Cinematic_Begin/End, AVI_Cinematic_FinalMission_*
-- AVI_Cinematic_Music_Trigger_Hope/Threat/Vista/Victory
-- AVI_Video_Intro_Start/Stop
-- Cutscene_WakeUp_*, Cutscene_VistaView_*
-- Cutscene_PodLanding_*, Cutscene_EpicJump_*
-- Cutscene_HighSeas_*, CutScene_StartIntroCinematic
-- Cutscene_ExplorationCutScene_*, Cutscene_ExplorationEnd*
-- Play_Cutscene_Finalmission_*
-- Ending_Cinematic_*, Ending_Explosion_Stringer
-- PIO_Intro_Video_*, PIO_Miranda_*
-- IGC_* (in-game cinematic events)
--
-- ---- PLAYER ----
-- Global_Player_Died_local/remote
-- Global_Player_SpawnTeleport, Global_Player_Spawnbegin
-- Global_Enter_BuildMode, Global_Exit_BuildMode
-- Global_GameStart, Global_Transformation_Start/End
-- Global_CriticalSituationSpeak, Global_DearColleagueSpeak
-- Global_Reset_RTPC
-- Core_Playing, Core_PreGameMenus
-- Core_TransitionToPlaySession_Default/TutorialToPioneers
-- LoadingScreen_planet_beginPodFlyBy/endPodFlyBy
-- IntroSpeak_Exploration_1..5
-- Salvage_Hit, Salvage_Explosive_Start/Stop
-- ShowHologram, HideHologram
-- Global_ExplorationSpeakIntro/Salvage/RecoveryDrones
-- Shared_BallAndGoal_activate/deactivate/GoalKick
-- Shared_Ball_materialize
-- Enemy_Hitmakers_Hit
-- Play_External_VO, MUS_TutorialStepComplete
--
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- 15. KNOWN QUIRKS & LIMITATIONS
-- Source: [MOD], [DOCS], [WORKSHOP]
--
-- 1. WriteAllText_Dynamic rejects empty strings.
--    Always use " " (a single space) to clear/reset a file.
--    Source: [MOD] discovered behavior
--
-- 2. ReadAllText_Dynamic returns "" for missing files.
--    It returns an empty string, NOT nil, for files that don't exist or
--    were never written by the mod.
--    Source: [MOD] discovered behavior
--
-- 3. Only 1 camera per player.
--    AddCamera will fail silently if a camera already exists for that player.
--    Source: [DOCS]:497
--
-- 4. Build complexity default is 700; higher values unstable.
--    SetBuildComplexity allows setting above 700 but the game may crash or
--    exhibit undefined behavior.
--    Source: [DOCS]:231
--
-- 5. Chat messages ignored in singleplayer.
--    SendChatMessage has no effect in singleplayer sessions.
--    Source: [DOCS]:648
--
-- 6. Block repair replaces destroyed blocks with new ones.
--    After a player repairs their structure, destroyed blocks are replaced
--    with entirely new ModBlock objects. Old references become invalid.
--    Always call Exists() before operating on cached block references.
--    Source: [DOCS]:2118
--
-- 7. SetDrag / SetDragAll are expensive operations.
--    Avoid calling these every frame. Cache and only update when needed.
--    Source: [DOCS]:1981, 1993
--
-- 8. TeleportAllPlayersToSpawnPoint supports max 8 players.
--    Source: [DOCS]:619
--
-- 9. Collision callbacks need string function names stored in _G.
--    RegisterFunctionToCollisionEnterCallback and Exit take a string name,
--    not a function reference. The function must be in the global table.
--    Source: [DOCS]:237, [WORKSHOP] trackmakermod
--
-- 10. Key binding callbacks need string function names stored in _G.
--     RegisterFunctionToKeyDownCallback and KeyUp follow the same pattern
--     as collision callbacks.
--     Source: [DOCS]:854, [MOD]
--
-- 11. Scale of exactly 1.0 on X axis may cause physics issues.
--     Use 1.00001 instead of 1.0 for the X component when setting scale.
--     Source: [WORKSHOP] mod 3304407501:127-129
--
-- 12. Spawn chain order matters.
--     After spawning an object, apply transforms in this order:
--     spawn -> SetRotation -> SetScale -> SetIsStatic -> SetIsVisible -> SetIsTrigger
--     Source: [WORKSHOP] multiple mods
--
-- 13. JSON parsing in Lua: "too complex" pattern error.
--     The game's built-in Lua pattern engine hits "too complex" errors on
--     regex-based JSON parsers. Use character-by-character parsing instead.
--     Source: [MOD] mod/main.lua hand-rolled JSON decoder
--
-- 14. SendChatMessage echoes back through OnChatMessage next frame.
--     The game asynchronously delivers the sent message back through
--     OnChatMessage on the next frame. Use echo suppression (count map
--     with TTL) to prevent infinite loops.
--     Source: [MOD] echo suppression in mod/main.lua
--
-- 15. tm.GetDocs() generates the full API docs string at runtime.
--     Can be called to dump the API reference as a string for inspection.
--     Source: [DOCS]:1360
--
-- 16. File I/O is limited: no rename, delete, glob, or directory listing.
--     Only WriteAllText_Dynamic and ReadAllText_Dynamic are available.
--     No file system operations like rename, delete, or listing files.
--     Source: [MOD], Trailmakers Lua sandbox
--
-- 17. Non-uniform scale may break physics.
--     Setting different X/Y/Z scale values can cause unpredictable physics
--     behavior on spawned objects.
--     Source: [DOCS]:1555
--
--------------------------------------------------------------------------------
