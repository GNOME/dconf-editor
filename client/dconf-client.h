#ifndef _dconf_client_h_
#define _dconf_client_h_

#include <glib.h>

typedef struct _DConfClient DConfClient;
typedef struct _DConfClientResetList DConfClientResetList;

typedef enum
{
  DCONF_CLIENT_READ_NORMAL,
  DCONF_CLIENT_READ_SET,
  DCONF_CLIENT_READ_RESET
} DConfClientReadType;

typedef struct
{
  gint         bus_type;
  const gchar *destination;
  const gchar *object_path;
  const gchar *interface;
  const gchar *method;
  GVariant    *body;
} DConfClientMessage;



typedef GVariant *    (*DConfClientServiceFunc)                         (DConfClient             *client,
                                                                         DConfClientMessage      *message);

DConfClient *           dconf_client_new                                (DConfClientServiceFunc   service_func);
void                    dconf_client_unref                              (DConfClient             *client);
DConfClient *           dconf_client_ref                                (DConfClient             *client);

GVariant *              dconf_client_read                               (DConfClient             *client,
                                                                         const gchar             *key,
                                                                         const GVariantType      *required_type,
                                                                         DConfClientReadType      type);
gchar **                dconf_client_list                               (DConfClient             *client,
                                                                         const gchar             *path,
                                                                         DConfClientResetList    *resets);

void                    dconf_client_get_service_info                   (DConfClient             *client,
                                                                         const gchar            **bus_type,
                                                                         const gchar            **destination,
                                                                         const gchar            **object_path);
gboolean                dconf_client_is_writable                        (DConfClient             *client,
                                                                         DConfClientMessage      *message,
                                                                         const gchar             *name);
gboolean                dconf_client_write                              (DConfClient             *client,
                                                                         DConfClientMessage      *message,
                                                                         const gchar             *key,
                                                                         GVariant                *value);
gboolean                dconf_client_write_tree                         (DConfClient             *client,
                                                                         DConfClientMessage      *message,
                                                                         GTree                   *tree);
void                    dconf_client_watch                              (DConfClient             *client,
                                                                         DConfClientMessage      *message,
                                                                         const gchar             *name);
void                    dconf_client_unwatch                            (DConfClient             *client,
                                                                         DConfClientMessage      *message,
                                                                         const gchar             *name);
void                    dconf_client_decode_notify                      (DConfClient             *client,
                                                                         const gchar            **prefix,
                                                                         const gchar           ***keys,
                                                                         GVariant                *body);

void                    dconf_client_reset_list_init                    (DConfClientResetList    *resets,
                                                                         const gchar * const     *list);
void                    dconf_client_reset_list_add                     (DConfClientResetList    *resets,
                                                                         const gchar             *item);
void                    dconf_client_reset_list_clear                   (DConfClientResetList    *resets);

#endif /* _dconf_client_h_ */
