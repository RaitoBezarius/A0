// Pages store
pub const REQUIRED_PAGES_COUNT = 4096;

// Identity mapped
pub const Stack = 0x80000;
pub const VRAM = 0xB8000;
pub const Kernel = 0x100000;
pub const Identity = 0x1600000;

// Kernel structures
pub const Temporary = 0x1600000;
pub const Heap = 0x1610000;

// TODO: User space

// Paging hiearchies
pub const PageTables = 0xFFC00000; // 4KB
pub const PageDirectory = 0xFFFFF000; // 2MB
pub const PageDirectoryPointer = 0x13FFFF000; // 1GB
pub const PageMapLevel4 = 0x813FFFF000; // 512GB
// For fun.
pub const PageMapLevel5 = 0x100813FFFF000; // 256TB
