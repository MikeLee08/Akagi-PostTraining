//! End-to-end numeric parity: the candle loader must reproduce the PyTorch
//! (folded) reference logits for a deterministic input. The reference JSON is
//! produced by `train/parity_check.py` next to the shipped weights.
#![cfg(feature = "infer")]

use std::fs;
use std::path::Path;

use native_bot::model::Model;

fn floats(v: &serde_json::Value) -> Vec<f32> {
    v.as_array()
        .unwrap()
        .iter()
        .map(|x| x.as_f64().unwrap() as f32)
        .collect()
}

fn argmax(v: &[f32]) -> usize {
    v.iter()
        .enumerate()
        .max_by(|a, b| a.1.partial_cmp(b.1).unwrap())
        .unwrap()
        .0
}

fn check(model_file: &str, parity_file: &str, num_players: u8) {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("weights");
    check_paths(&dir.join(model_file), &dir.join(parity_file), num_players);
}

fn check_paths(model_file: &Path, parity_file: &Path, num_players: u8) {
    let bytes = fs::read(model_file).expect("weights present");
    let model = Model::from_safetensors(bytes, num_players).expect("load model");

    let json: serde_json::Value =
        serde_json::from_slice(&fs::read(parity_file).expect("parity json")).unwrap();
    let input = floats(&json["input"]);
    let reference = floats(&json["logits"]);

    let got = model.forward_logits(&input).expect("forward");
    assert_eq!(got.len(), reference.len(), "logit length mismatch");

    let max_diff = got
        .iter()
        .zip(&reference)
        .map(|(a, b)| (a - b).abs())
        .fold(0.0f32, f32::max);
    assert_eq!(
        argmax(&got),
        json["argmax"].as_u64().unwrap() as usize,
        "candle argmax differs from PyTorch"
    );
    assert!(
        max_diff < 2e-3,
        "candle vs PyTorch logit diff too large: {max_diff}"
    );
    eprintln!(
        "{}: candle/PyTorch max|diff| = {max_diff:.2e}, argmax matches",
        model_file.display()
    );
}

#[test]
fn parity_4p() {
    check("akagi4p.safetensors", "parity_4p.json", 4);
}

#[test]
fn parity_3p() {
    check("akagi3p.safetensors", "parity_3p.json", 3);
}

#[test]
fn candidate_3p_from_env() {
    let Ok(model_file) = std::env::var("AKAGI_3P_CANDIDATE_WEIGHTS") else {
        return;
    };
    let parity_file =
        std::env::var("AKAGI_3P_CANDIDATE_PARITY").expect("candidate parity path is required");
    check_paths(Path::new(&model_file), Path::new(&parity_file), 3);
}
