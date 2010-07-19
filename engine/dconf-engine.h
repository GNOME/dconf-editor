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
  const GVariantType *reply_type;
  GVariant    *body;
} DConfEngineMessage;



typedef GVariant *    (*DConfEngineServiceFunc)                         (DConfEngineMessage      *message);

void                    dconf_engine_set_service_func                   (DConfEngineServiceFunc   func);
DConfEngine *           dconf_engine_new                                (const gchar             *profile);
DConfEngine *           dconf_engine_new_for_db                         (DConfEngineServiceFunc  *service,
                                                                         const gchar             *db_name);
guint64                 dconf_engine_get_state                          (DConfEngine             *engine);

void                    dconf_engine_unref                              (DConfEngine             *engine);
DConfEngine *           dconf_engine_ref                                (DConfEngine             *engine);

GVariant *              dconf_engine_read                               (DConfEngine             *engine,
                                                                         const gchar             *key,
                                                                         DConfReadType            type);
gchar **                dconf_engine_list                               (DConfEngine             *engine,
                                                                         const gchar             *path,
                                                                         DConfResetList          *resets,
                                                                         gsize                   *length);

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
gboolean                dconf_engine_write_many                         (DConfEngine             *engine,
                                                                         DConfEngineMessage      *message,
                                                                         const gchar             *prefix,
                                                                         const gchar * const     *keys,
                                                                         GVariant               **values,
                                                                         GError                 **error);
void                    dconf_engine_watch                              (DConfEngine             *engine,
                                                                         DConfEngineMessage      *message,
                                                                         const gchar             *name);
void                    dconf_engine_unwatch                            (DConfEngine             *engine,
                                                                         DConfEngineMessage      *message,
                                                                         const gchar             *name);
gboolean                dconf_engine_decode_notify                      (DConfEngine             *engine,
                                                                         const gchar             *anti_expose,
                                                                         const gchar            **prefix,
                                                                         const gchar           ***keys,
                                                                         guint                    bus_type,
                                                                         const gchar             *sender,
                                                                         const gchar             *interface,
                                                                         const gchar             *member,
                                                                         GVariant                *body);
void                    dconf_engine_set_lock                           (DConfEngine             *engine,
                                                                         DConfEngineMessage      *message,
                                                                         const gchar             *path,
                                                                         gboolean                 locked);

gboolean                dconf_engine_interpret_reply                    (DConfEngineMessage      *message,
                                                                         const gchar             *sender,
                                                                         GVariant                *body,
                                                                         gchar                  **tag,
                                                                         GError                 **error);

#endif /* _dconf_engine_h_ */
