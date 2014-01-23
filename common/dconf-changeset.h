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

#ifndef __dconf_changeset_h__
#define __dconf_changeset_h__

#include <glib.h>

typedef struct _DConfChangeset                              DConfChangeset;

typedef gboolean     (* DConfChangesetPredicate)                        (const gchar              *path,
                                                                         GVariant                 *value,
                                                                         gpointer                  user_data);

DConfChangeset *        dconf_changeset_new                             (void);
DConfChangeset *        dconf_changeset_new_database                    (DConfChangeset           *copy_of);

DConfChangeset *        dconf_changeset_new_write                       (const gchar              *path,
                                                                         GVariant                 *value);

DConfChangeset *        dconf_changeset_ref                             (DConfChangeset           *changeset);
void                    dconf_changeset_unref                           (DConfChangeset           *changeset);

gboolean                dconf_changeset_is_empty                        (DConfChangeset           *changeset);

void                    dconf_changeset_set                             (DConfChangeset           *changeset,
                                                                         const gchar              *path,
                                                                         GVariant                 *value);

gboolean                dconf_changeset_get                             (DConfChangeset           *changeset,
                                                                         const gchar              *key,
                                                                         GVariant                **value);

gboolean                dconf_changeset_is_similar_to                   (DConfChangeset           *changeset,
                                                                         DConfChangeset           *other);

gboolean                dconf_changeset_all                             (DConfChangeset           *changeset,
                                                                         DConfChangesetPredicate   predicate,
                                                                         gpointer                  user_data);

guint                   dconf_changeset_describe                        (DConfChangeset           *changeset,
                                                                         const gchar             **prefix,
                                                                         const gchar * const     **paths,
                                                                         GVariant * const        **values);

GVariant *              dconf_changeset_serialise                       (DConfChangeset           *changeset);
DConfChangeset *        dconf_changeset_deserialise                     (GVariant                 *serialised);

void                    dconf_changeset_change                          (DConfChangeset           *changeset,
                                                                         DConfChangeset           *changes);

DConfChangeset *        dconf_changeset_diff                            (DConfChangeset           *from,
                                                                         DConfChangeset           *to);

void                    dconf_changeset_seal                            (DConfChangeset           *changeset);

#endif /* __dconf_changeset_h__ */
