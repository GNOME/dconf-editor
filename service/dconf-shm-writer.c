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
 * License along with this library; if not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

#include "config.h"

#include "dconf-writer.h"

typedef DConfWriterClass DConfShmWriterClass;
typedef DConfWriter DConfShmWriter;

G_DEFINE_TYPE (DConfShmWriter, dconf_shm_writer, DCONF_TYPE_WRITER)

static void
dconf_shm_writer_list (GHashTable *set)
{
}

static void
dconf_shm_writer_init (DConfWriter *writer)
{
  dconf_writer_set_basepath (writer, "shm");
}

static void
dconf_shm_writer_class_init (DConfWriterClass *class)
{
  class->list = dconf_shm_writer_list;
}
