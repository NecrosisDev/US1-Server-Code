-- Immutable-by-convention defaults from the approved v3 contract.
return {
    version="3.3.0-shadow.2", policy="zcity-adjudication-v3.1", server="450e82aa",
    enforcement_available=false, -- No console variable can enable a second live writer.
    maximum=120000000, minimum=-60000000, units=1000000,
    minor_seconds=3, minor_actions=1, escalation_actions=3,
    escalation_harm=1, escalation_seconds=5, serious_seconds=12,
    heartbeat_seconds=1, disengagement_seconds=2, incapacity_seconds=1,
    witness_distance=1024, witness_seconds=3, separation=512,
    tolerance_harm=0.5, tolerance_actions=2, tolerance_seconds=120,
    control_gap=10, control_floor={refused_grab=0.25,restrict=0.5,danger=1},
    review_seconds=45, maximum_harm=10, respect=3,
    brain={grace=20,decay=2,delay=3,scale=0.0005,burst_time=0.5,
        burst_cap=0.0175,life_cap=0.10,ceiling=0.125,passive_mild=0.075,
        weights={unarmed=0.25,other=0.75,bullet=1.25,blast=1.50}},
    capacity={queue=4096,events_per_tick=64,ring=512,lives=4096,
        contexts=32,actions=8192,conditions=8192,log_bytes=2097152},
    gates={rounds=10,events=200,reviewed=30,players=36,p95_ms=1},
}
