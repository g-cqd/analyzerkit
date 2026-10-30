---
status: not-started
blocked-by: []
date: 2026-10-31
---

# 0060 — Index coverage before the database import (A1′)

`IndexStoreSession.open` imports the store into an IndexStoreDB database, then classifies the analyzed files. On
maintastic the first import took 9.4 s and 128 MB (A1′, research 2026-10-29). A store that covers none of the files is
then refused, after the import is paid. arcleak (0023) and deadwood (0024) both open through the session.

Do: decide `isUsable` before the import where the store allows it. The store's unit files name their main source file,
and the units directory can be read without IndexStoreDB (libIndexStore's unit reader, or the unit file's header). Only
when some analyzed file has a unit is the database imported. A store whose units cannot be read this way keeps today's
order.

Red: a store built for other files is refused with no database directory created under the cache root, and in well
under the time of an import (the fixture's import as the bound). A store that covers one analyzed file opens as now.
