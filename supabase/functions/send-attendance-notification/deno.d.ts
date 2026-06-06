declare const Deno: {
  env: { get(key: string): string | undefined };
};

declare module "https://deno.land/std@*";
declare module "https://esm.sh/*";
