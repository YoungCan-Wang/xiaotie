export {};

declare global {
  interface Window {
    xiaotie: {
      listItems: (filter: { query: string; groupId: string }) => Promise<
        Array<{
          id: string;
          type: "text";
          text: string;
          createdAt: number;
          lastSeenAt: number;
          lastCopiedAt: number | null;
          pinned: boolean;
          groupIds: string[];
        }>
      >;
      listGroups: () => Promise<
        Array<{
          id: string;
          name: string;
          createdAt: number;
          protected?: boolean;
        }>
      >;
      createGroup: (name: string) => Promise<{ ok: boolean; group?: { id: string; name: string } }>;
      renameGroup: (id: string, name: string) => Promise<{ ok: boolean }>;
      deleteGroup: (id: string) => Promise<{ ok: boolean }>;
      toggleItemGroup: (itemId: string, groupId: string) => Promise<{ ok: boolean }>;
      copyItem: (id: string) => Promise<{ ok: boolean }>;
      togglePinned: (id: string) => Promise<unknown>;
      deleteItem: (id: string) => Promise<unknown>;
      clearAll: () => Promise<unknown>;
      hideWindow: () => Promise<boolean>;
      onUpdated: (handler: () => void) => () => void;
    };
  }
}
