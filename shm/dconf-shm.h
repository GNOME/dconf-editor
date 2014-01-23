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
 * License along with this library; if not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

#ifndef __dconf_shm_h__
#define __dconf_shm_h__

#include <glib.h>

G_GNUC_INTERNAL
guint8 *                dconf_shm_open                                  (const gchar *name);
G_GNUC_INTERNAL
void                    dconf_shm_close                                 (guint8      *shm);
G_GNUC_INTERNAL
void                    dconf_shm_flag                                  (const gchar *name);

static inline gboolean
dconf_shm_is_flagged (const guint8 *shm)
{
  return shm == NULL || *shm != 0;
}

#endif /* __dconf_shm_h__ */
