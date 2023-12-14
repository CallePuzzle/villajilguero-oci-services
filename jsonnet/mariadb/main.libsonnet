local database = import 'database.libsonnet';
local instance = import 'instance.libsonnet';

std.objectValues(instance + database)
