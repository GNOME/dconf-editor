#ifndef _dconf_engine_h_
#define _dconf_engine_h_

#include <glib.h>

typedef struct _DConfEngine DConfEngine;
typedef struct _DConfEngineResetList DConfEngineResetList;

typedef enum
{
  DCONF_ENGINE_READ_NORMAL,
  DCONF_ENGINE_READ_SET,
  DCONF_ENGINE_READ_RESET
} DConfEngineReadType;

typedef struct
{
  gint         bus_type;
  const gchar *destination;
  const gchar *object_path;
  const gchar *interface;
  const gchar *method;
  GVariant    *body;
} DConfEngineMessage;



typedef GVariant *    (*DConfEngineServiceFunc)                         (DConfEngine             *engine,
                                                                         DConfEngineMessage      *message);

DConfEngine *           dconf_engine_new                                (DConfEngineServiceFunc   service_func);
void                    dconf_engine_unref                              (DConfEngine             *engine);
DConfEngine *           dconf_engine_ref                                (DConfEngine             *engine);

GVariant *              dconf_engine_read                               (DConfEngine             *engine,
                                                                         const gchar             *key,
                                                                         const GVariantType      *required_type,
                                                                         DConfEngineReadType      type);
gchar **                dconf_engine_list                               (DConfEngine             *engine,
                                                                         const gchar             *path,
                                                                         DConfEngineResetList    *resets);

void                    dconf_engine_get_service_info                   (DConfEngine             *engine,
                                                                         const gchar            **bus_type,
                                                                         const gchar            **destination,
                                                                         const gchar            **object_path);
gboolean                dconf_engine_is_writable                        (DConfEngine             *engine,
                                                                         DConfEngineMessage      *message,
                                                                         const gchar             *name);
gboolean                dconf_engine_write                              (DConfEngine             *engine,
                                                                         DConfEngineMessage      *message,
                                                                         const gchar             *key,
                                                                         GVariant                *value);
gboolean                dconf_engine_write_tree                         (DConfEngine             *engine,
                                                                         DConfEngineMessage      *message,
                                                                         GTree                   *tree);
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

void                    dconf_engine_reset_list_init                    (DConfEngineResetList    *resets,
                                                                         const gchar * const     *list);
void                    dconf_engine_reset_list_add                     (DConfEngineResetList    *resets,
                                                                         const gchar             *item);
void                    dconf_engine_reset_list_clear                   (DConfEngineResetList    *resets);

#endif /* _dconf_engine_h_ */
