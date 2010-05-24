#ifndef _dconf_engine_h_
#define _dconf_engine_h_

#include <dconf-readtype.h>
#include <dconf-resetlist.h>
#include <glib.h>

typedef struct _DConfEngine DConfEngine;

typedef struct
{
  gint         bus_type;
  const gchar *destination;
  const gchar *object_path;
  const gchar *interface;
  const gchar *method;
  const gchar *reply_type;
  GVariant    *body;
} DConfEngineMessage;



typedef GVariant *    (*DConfEngineServiceFunc)                         (DConfEngine             *engine,
                                                                         DConfEngineMessage      *message);

DConfEngine *           dconf_engine_new                                (const gchar             *context);
void                    dconf_engine_unref                              (DConfEngine             *engine);
DConfEngine *           dconf_engine_ref                                (DConfEngine             *engine);

GVariant *              dconf_engine_read                               (DConfEngine             *engine,
                                                                         const gchar             *key,
                                                                         DConfReadType            type);
gchar **                dconf_engine_list                               (DConfEngine             *engine,
                                                                         const gchar             *path,
                                                                         DConfResetList          *resets);

void                    dconf_engine_get_service_info                   (DConfEngine             *engine,
                                                                         const gchar            **bus_type,
                                                                         const gchar            **destination,
                                                                         const gchar            **object_path);
gboolean                dconf_engine_is_writable                        (DConfEngine             *engine,
                                                                         DConfEngineMessage      *message,
                                                                         const gchar             *name,
                                                                         GError                 **error);
gboolean                dconf_engine_write                              (DConfEngine             *engine,
                                                                         DConfEngineMessage      *message,
                                                                         const gchar             *key,
                                                                         GVariant                *value,
                                                                         GError                 **error);
gboolean                dconf_engine_write_tree                         (DConfEngine             *engine,
                                                                         DConfEngineMessage      *message,
                                                                         GTree                   *tree,
                                                                         GError                 **error);
void                    dconf_engine_watch                              (DConfEngine             *engine,
                                                                         DConfEngineMessage      *message,
                                                                         const gchar             *name);
void                    dconf_engine_unwatch                            (DConfEngine             *engine,
                                                                         DConfEngineMessage      *message,
                                                                         const gchar             *name);
void                    dconf_engine_decode_notify                      (DConfEngine             *engine,
                                                                         const gchar            **prefix,
                                                                         const gchar           ***keys,
                                                                         GVariant                *body);

#endif /* _dconf_engine_h_ */
