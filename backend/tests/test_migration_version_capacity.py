from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
from types import SimpleNamespace


MIGRATIONS_DIR = Path(__file__).resolve().parents[1] / "alembic" / "versions"


def _load_migration(filename: str):
    spec = spec_from_file_location(f"test_{filename[:-3]}", MIGRATIONS_DIR / filename)
    assert spec is not None and spec.loader is not None
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_0012_widens_version_column_before_long_0013_revision(monkeypatch):
    revision_0012 = _load_migration("0012_retired_tank_lifecycle.py")
    revision_0013 = _load_migration("0013_persistent_monitoring_incidents.py")
    assert len(revision_0013.revision) == 36

    operations = []
    migration_op = SimpleNamespace(
        alter_column=lambda *args, **kwargs: operations.append((args, kwargs))
    )
    monkeypatch.setattr(revision_0012, "op", migration_op)

    postgresql = SimpleNamespace(dialect=SimpleNamespace(name="postgresql"))
    revision_0012._widen_alembic_version_table(postgresql)

    assert len(operations) == 1
    args, kwargs = operations[0]
    assert args == ("alembic_version", "version_num")
    assert kwargs["existing_type"].length == 32
    assert kwargs["type_"].length == 64

    sqlite = SimpleNamespace(dialect=SimpleNamespace(name="sqlite"))
    revision_0012._widen_alembic_version_table(sqlite)
    assert len(operations) == 1
