import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { HomePage } from "./HomePage";

describe("HomePage", () => {
  it("is titled Baby Sweepstake", () => {
    render(<HomePage />);

    expect(
      screen.getByRole("heading", { level: 1, name: "Baby Sweepstake" }),
    ).toBeInTheDocument();
  });
});
