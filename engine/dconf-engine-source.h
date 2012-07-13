/*
 * Copyright © 2010 Codethink Limited
 * Copyright © 2012 Canonical Limited
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the licence, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

#ifndef __dconf_engine_source_h__
#define __dconf_engine_source_h__

#include "../gvdb/gvdb-reader.h"
#include <gio/gio.h>

typedef struct _DConfEngineSourceVTable DConfEngineSourceVTable;
typedef struct _DConfEngineSource DConfEngineSource;

struct _DConfEngineSourceVTable
{
  gsize instance_size;

  void          (* init)             (DConfEngineSource *source);
  void          (* finalize)         (DConfEngineSource *source);
  gboolean      (* needs_reopen)     (DConfEngineSource *source);
  GvdbTable *   (* reopen)           (DConfEngineSource *source);
};

struct _DConfEngineSource
{
  const DConfEngineSourceVTable *vtable;

  GvdbTable *values;
  GvdbTable *locks;
  GBusType   bus_type;
  gboolean   writable;
  gchar     *bus_name;
  gchar     *object_path;
  gchar     *name;
};

G_GNUC_INTERNAL
void                    dconf_engine_source_free                        (DConfEngineSource  *source);

G_GNUC_INTERNAL
gboolean                dconf_engine_source_refresh                     (DConfEngineSource  *source);

G_GNUC_INTERNAL
DConfEngineSource *     dconf_engine_source_new                         (const gchar        *name);

G_GNUC_INTERNAL
DConfEngineSource *     dconf_engine_source_new_default                 (void);

#endif /* __dconf_engine_source_h__ */
