/*
 * Copyright © 2007, 2008  Ryan Lortie
 * Copyright © 2009 Codethink Limited
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * as published by the Free Software Foundation; either version 2.1
 * of the licence, or (at your option) any later version.
 *
 * See the included COPYING file for more information.
 *
 * Authors: Ryan Lortie <desrt@desrt.ca>
 */

#ifndef _dconfstorage_h_
#define _dconfstorage_h_

#include <gio/gsettingsbackend.h>

#define DCONF_TYPE_STORAGE                                  (dconf_storage_get_type ())
#define DCONF_STORAGE(inst)                                 (G_TYPE_CHECK_INSTANCE_CAST ((inst),                             \
                                                             DCONF_TYPE_STORAGE, DConfStorage))
typedef struct OPAQUE_TYPE__DConfStorage                    DConfStorage;
typedef struct OPAQUE_TYPE__DConfStorageClass               DConfStorageClass;

G_BEGIN_DECLS

GType                           dconf_storage_get_type                  (void);

G_END_DECLS

#endif /* _dconfstorage_h_ */
