pub const Size = struct {
    pub const widget_width: i32 = 380;
    pub const widget_height: i32 = 220;
    pub const padding: i32 = 14;
    pub const slider_height: f32 = 4.0;
    pub const slider_thumb_radius: f32 = 6.0;
    pub const button_height: i32 = 32;
    pub const button_radius: f32 = 6.0;
    pub const button_nav_size: i32 = 32;
    pub const corner_radius: f32 = 10.0;
    pub const icon_speaker_size: i32 = 24;
};

pub const Color = struct {
    pub const background: u32 = 0xFF1A1A1A;
    pub const surface: u32 = 0xFF2A2A2A;
    pub const surface_hover: u32 = 0xFF3A3A3A;
    pub const border: u32 = 0xFF404040;
    pub const accent: u32 = 0xFF3B82F6;
    pub const accent_hover: u32 = 0xFF5B9CF6;
    pub const text: u32 = 0xFFFFFFFF;
    pub const text_dim: u32 = 0xFF909090;
    pub const slider_track: u32 = 0xFF3F3F3F;
    pub const muted: u32 = 0xFFEF4444;
    pub const glow: u32 = 0x20FFFFFF;
};
