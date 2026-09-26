-- Library loader; returned modules have no live runtime side effects.
local U=include("zc_justice_v3/util.lua")
local C=include("zc_justice_v3/config.lua")
local P=include("zc_justice_v3/pricing.lua")(U,C)
return {U=U,C=C,P=P,Adjudicator=include("zc_justice_v3/adjudicator.lua")(U,C,P),
    Lifecycle=include("zc_justice_v3/lifecycle.lua")(U,C),
    Provenance=include("zc_justice_v3/provenance.lua")(U,C),
    Ledger=include("zc_justice_v3/ledger.lua")(U,C,P),
    MemoryStore=include("zc_justice_v3/store_memory.lua")(U),
    SQLiteStore=include("zc_justice_v3/store_sqlite.lua")(U),
    Modes=include("zc_justice_v3/modes.lua")(U,C)}
