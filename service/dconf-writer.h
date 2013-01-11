/*
 * Copyright © 2010 Codethink Limited
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

#ifndef __dconf_writer_h__
#define __dconf_writer_h__

#include <gio/gio.h>

#include "../common/dconf-changeset.h"
#include "dconf-generated.h"

#define DCONF_TYPE_WRITER                                   (dconf_writer_get_type ())
#define DCONF_WRITER(inst)                                  (G_TYPE_CHECK_INSTANCE_CAST ((inst),                     \
                                                             DCONF_TYPE_WRITER, DConfWriter))
#define DCONF_WRITER_CLASS(class)                           (G_TYPE_CHECK_CLASS_CAST ((class),                       \
                                                             DCONF_TYPE_WRITER, DConfWriterClass))
#define DCONF_IS_WRITER(inst)                               (G_TYPE_CHECK_INSTANCE_TYPE ((inst),                     \
                                                             DCONF_TYPE_WRITER))
#define DCONF_IS_WRITER_CLASS(class)                        (G_TYPE_CHECK_CLASS_TYPE ((class),                       \
                                                             DCONF_TYPE_WRITER))
#define DCONF_WRITER_GET_CLASS(inst)                        (G_TYPE_INSTANCE_GET_CLASS ((inst),                      \
                                                             DCONF_TYPE_WRITER, DConfWriterClass))

typedef struct _DConfWriterPrivate                          DConfWriterPrivate;
typedef struct _DConfWriterClass                            DConfWriterClass;
typedef struct _DConfWriter                                 DConfWriter;

struct _DConfWriterClass
{
  DConfDBusWriterSkeletonClass parent_instance;

  /* static methods */
  void     (* list)   (GHashTable      *set);

  /* instance methods */
  gboolean (* begin)  (DConfWriter     *writer,
                       GError         **error);
  void     (* change) (DConfWriter     *writer,
                       DConfChangeset  *changeset,
                       const gchar     *tag);
  gboolean (* commit) (DConfWriter     *writer,
                       GError         **error);
  void     (* end)    (DConfWriter     *writer);
};

struct _DConfWriter
{
  DConfDBusWriterSkeleton parent_instance;
  DConfWriterPrivate *priv;
};


GType                   dconf_writer_get_type                           (void);

void                    dconf_writer_set_basepath                       (DConfWriter *writer,
                                                                         const gchar *name);
DConfChangeset *        dconf_writer_diff                               (DConfWriter *writer,
                                                                         DConfChangeset *changeset);
const gchar *           dconf_writer_get_name                           (DConfWriter *writer);

void                    dconf_writer_list                               (GType        type,
                                                                         GHashTable  *set);
GDBusInterfaceSkeleton *dconf_writer_new                                (GType        type,
                                                                         const gchar *name);

#define DCONF_TYPE_SHM_WRITER                               (dconf_shm_writer_get_type ())
GType                   dconf_shm_writer_get_type                       (void);
#define DCONF_TYPE_KEYFILE_WRITER                           (dconf_keyfile_writer_get_type ())
GType                   dconf_keyfile_writer_get_type                   (void);

#endif /* __dconf_writer_h__ */
