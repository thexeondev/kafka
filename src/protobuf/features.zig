const remielle = @import("../remielle.zig");
const gen = remielle.protobuf.gen;

pub const hall_npcs: bool =
    @hasDecl(gen, "NpcInfo") and
    @hasDecl(gen, "InteractInfo") and
    @hasField(gen.NpcInfo, "npc_id") and
    @hasField(gen.NpcInfo, "is_active");

pub const hall_time: bool =
    @hasField(gen.HallSceneData, "day_of_week") and
    @hasField(gen.HallSceneData, "scene_time_in_minutes");

pub const hall_refresh: bool =
    @hasDecl(gen, "HallRefreshScNotify") and
    @hasField(gen.HallRefreshScNotify, "force_refresh");

pub const avatar_sync: bool =
    @hasField(gen.PlayerSyncScNotify, "avatar");

pub const big_scene_avatars: bool =
    @hasDecl(gen, "BigSceneAvatarInfo");

pub const big_scene_sync: bool =
    big_scene_avatars and @hasField(gen.PlayerSyncScNotify, "big_scene");

pub const big_scene_floor: bool =
    @hasDecl(gen, "EnterFloorScNotify");
