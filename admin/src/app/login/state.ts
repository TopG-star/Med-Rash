export type LoginActionState = {
  status: "idle" | "sent" | "error";
  message: string;
};

export const initialLoginState: LoginActionState = { status: "idle", message: "" };
