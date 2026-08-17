from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, StrictBool, StrictInt, StrictStr, model_validator


LIGHT_TIMER_MAX_MS = 86_400_000
FEEDER_ANGLE_MIN = 0
FEEDER_ANGLE_MAX = 180
FEEDER_DURATION_MIN_MS = 500
FEEDER_DURATION_MAX_MS = 60_000
PUMP_COMMAND_EXPIRY_DEFAULT_SECONDS = 20
PUMP_COMMAND_EXPIRY_MAX_SECONDS = 30
FEEDER_SCHEDULE_SLOTS = 3
COMMAND_EXPIRY_DEFAULT_SECONDS = 120
COMMAND_EXPIRY_MAX_SECONDS = 300
TIME_PATTERN = r"^(?:[01]\d|2[0-3]):[0-5]\d$"

ActuatorName = Literal["uv", "led", "feeder", "pump_a", "pump_b"]
ActuatorAction = Literal["on", "off", "timer", "schedule", "feed_now", "config", "dispense", "stop", "retract"]
CommandStatus = Literal["queued", "executing", "succeeded", "failed", "expired"]


class DeviceCreate(BaseModel):
    device_id: str = Field(min_length=3, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    tank_id: int = Field(gt=0)


class DeviceProvisioned(BaseModel):
    device_id: str
    tank_id: int
    device_key: str


class LightTimerPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")

    duration_ms: StrictInt = Field(ge=1, le=LIGHT_TIMER_MAX_MS)


class LightSchedulePayload(BaseModel):
    model_config = ConfigDict(extra="forbid")

    enabled: StrictBool
    on_time: StrictStr = Field(pattern=TIME_PATTERN)
    off_time: StrictStr = Field(pattern=TIME_PATTERN)


class FeederConfigPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")

    open_angle: StrictInt = Field(ge=FEEDER_ANGLE_MIN, le=FEEDER_ANGLE_MAX)
    duration_ms: StrictInt = Field(ge=FEEDER_DURATION_MIN_MS, le=FEEDER_DURATION_MAX_MS)


class FeederScheduleSlot(BaseModel):
    model_config = ConfigDict(extra="forbid")

    enabled: StrictBool
    time: StrictStr = Field(pattern=TIME_PATTERN)


class FeederSchedulePayload(BaseModel):
    model_config = ConfigDict(extra="forbid")

    slots: list[FeederScheduleSlot] = Field(min_length=FEEDER_SCHEDULE_SLOTS, max_length=FEEDER_SCHEDULE_SLOTS)


class ActuatorCommandCreate(BaseModel):
    """Admin command input; payload is normalized to the bridge contract."""

    model_config = ConfigDict(extra="forbid")

    device_id: str | None = Field(default=None, min_length=3, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    actuator: ActuatorName
    action: ActuatorAction
    payload: dict[str, Any] = Field(default_factory=dict)
    expires_in_seconds: int | None = Field(default=None, ge=1, le=COMMAND_EXPIRY_MAX_SECONDS)

    @model_validator(mode="after")
    def validate_command_payload(self) -> "ActuatorCommandCreate":
        expected = {
            "uv": {"on", "off", "timer", "schedule"},
            "led": {"on", "off", "timer", "schedule"},
            "feeder": {"feed_now", "config", "schedule"},
            "pump_a": {"dispense", "stop", "retract"},
            "pump_b": {"dispense", "stop", "retract"},
        }[self.actuator]
        if self.action not in expected:
            raise ValueError(f"Action {self.action!r} is not allowed for {self.actuator}")

        if self.expires_in_seconds is None:
            self.expires_in_seconds = (
                PUMP_COMMAND_EXPIRY_DEFAULT_SECONDS
                if self.actuator in {"pump_a", "pump_b"}
                else COMMAND_EXPIRY_DEFAULT_SECONDS
            )
        elif self.actuator in {"pump_a", "pump_b"} and self.expires_in_seconds > PUMP_COMMAND_EXPIRY_MAX_SECONDS:
            raise ValueError(f"Pump commands must expire within {PUMP_COMMAND_EXPIRY_MAX_SECONDS} seconds")

        if self.action in {"on", "off", "feed_now"}:
            if self.payload:
                raise ValueError("This action does not accept a payload")
            self.payload = {}
        elif self.action == "timer":
            self.payload = LightTimerPayload.model_validate(self.payload).model_dump()
        elif self.action == "schedule" and self.actuator in {"uv", "led"}:
            self.payload = LightSchedulePayload.model_validate(self.payload).model_dump()
        elif self.action == "config":
            self.payload = FeederConfigPayload.model_validate(self.payload).model_dump()
        elif self.action == "schedule":
            self.payload = FeederSchedulePayload.model_validate(self.payload).model_dump()
        elif self.action == "dispense":
            # The received firmware's dispense route starts the volume
            # configured inside the firmware and accepts no query payload.
            # The bridge waits for that configured move to finish; a time
            # value here would be a safety cutoff, not a measured volume.
            if self.payload:
                raise ValueError("Pump dispense uses the firmware-configured volume and does not accept a payload")
            self.payload = {}
        elif self.action in {"stop", "retract"}:
            if self.payload:
                raise ValueError("This pump action does not accept a payload")
            self.payload = {}
        return self


class ActuatorCommandRead(BaseModel):
    command_id: str
    tank_id: int
    device_id: str
    actor_user_id: int | None
    actor_name: str | None
    actuator: ActuatorName
    action: ActuatorAction
    payload: dict[str, Any]
    status: CommandStatus
    requested_at: datetime
    expires_at: datetime
    executing_at: datetime | None = None
    execution_at: datetime | None = None
    result: dict[str, Any] | None = None
    error: str | None = None


class ActuatorHistorySummary(BaseModel):
    total: int
    queued: int
    executing: int
    succeeded: int
    failed: int
    expired: int


class ActuatorCommandHistoryPage(BaseModel):
    items: list[ActuatorCommandRead]
    page: int
    page_size: int
    total: int
    total_pages: int
    has_previous: bool
    has_next: bool
    summary: ActuatorHistorySummary


class PendingActuatorCommand(BaseModel):
    command_id: str
    device_id: str
    actuator: ActuatorName
    action: ActuatorAction
    payload: dict[str, Any]
    requested_at: datetime
    expires_at: datetime


class ActuatorCommandResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    result: dict[str, Any] = Field(default_factory=dict)


class ActuatorCommandFailure(BaseModel):
    model_config = ConfigDict(extra="forbid")

    error: StrictStr = Field(min_length=1, max_length=500)
    result: dict[str, Any] = Field(default_factory=dict)


class LightActuatorState(BaseModel):
    model_config = ConfigDict(extra="forbid")

    on: StrictBool
    remaining_ms: StrictInt = Field(ge=0, le=LIGHT_TIMER_MAX_MS)
    total_on_ms: StrictInt = Field(ge=0, le=4_294_967_295)
    schedule_enabled: StrictBool
    on_time: StrictStr = Field(pattern=TIME_PATTERN)
    off_time: StrictStr = Field(pattern=TIME_PATTERN)


class FeederActuatorState(BaseModel):
    model_config = ConfigDict(extra="forbid")

    feeding: StrictBool
    feed_count: StrictInt = Field(ge=0, le=2_147_483_647)
    last_fed: StrictStr = Field(max_length=80)
    open_angle: StrictInt = Field(ge=FEEDER_ANGLE_MIN, le=FEEDER_ANGLE_MAX)
    duration_ms: StrictInt = Field(ge=FEEDER_DURATION_MIN_MS, le=FEEDER_DURATION_MAX_MS)
    schedule: list[FeederScheduleSlot] = Field(min_length=FEEDER_SCHEDULE_SLOTS, max_length=FEEDER_SCHEDULE_SLOTS)


class PumpActuatorState(BaseModel):
    model_config = ConfigDict(extra="forbid")

    active: StrictBool
    dose_count: StrictInt = Field(ge=0, le=2_147_483_647)
    last_dispensed: StrictStr = Field(max_length=80)
    volume_ml: float = Field(ge=0, le=100)


class ActuatorStateReport(BaseModel):
    model_config = ConfigDict(extra="forbid")

    device_id: str | None = Field(default=None, min_length=3, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    actuator: ActuatorName
    state: dict[str, Any]
    command_id: str | None = Field(default=None, min_length=1, max_length=64)

    @model_validator(mode="after")
    def validate_state(self) -> "ActuatorStateReport":
        state_model: BaseModel
        if self.actuator in {"uv", "led"}:
            state_model = LightActuatorState.model_validate(self.state)
        elif self.actuator == "feeder":
            state_model = FeederActuatorState.model_validate(self.state)
        else:
            state_model = PumpActuatorState.model_validate(self.state)
        self.state = state_model.model_dump()
        return self


class ActuatorStateRead(BaseModel):
    actuator: ActuatorName
    state: dict[str, Any] | None
    refreshed_at: datetime | None


class DeviceActuatorStatusRead(BaseModel):
    tank_id: int
    device_id: str
    device_online: bool
    device_freshness: Literal["online", "offline", "unknown"]
    last_seen_at: datetime | None
    checked_at: datetime
    actuators: list[ActuatorStateRead]
